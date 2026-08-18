require 'ostruct'

module SpatialFeatures
  module Importers
    class KML < Base
      # <SimpleData name> keys that may contain <img> tags
      IMAGE_METADATA_KEYS = %w[pdfmaps_photos].freeze

      # The elements that become features. A Placemark holds them directly or inside a
      # MultiGeometry, and each one becomes a feature of its own.
      GEOMETRY_TYPES = %w[Polygon LineString Point].freeze
      GEOMETRY_SELECTOR = GEOMETRY_TYPES.join(', ').freeze

      # Matches what `GEOMETRY_SELECTOR` matches, for the path that scopes elements to one
      # Placemark by counting how many Placemarks they sit inside.
      GEOMETRY_SELF_TEST = GEOMETRY_TYPES.map {|type| "self::#{type}" }.join(' or ').freeze

      # Geometry that sits outside any Placemark, which imports with no name and no
      # metadata. One pass over the document matches all of it.
      UNPLACED_GEOMETRY_XPATH =
        GEOMETRY_TYPES.map {|type| "//#{type}[not(ancestor::Placemark)]" }.join(' | ').freeze

      # How many geometry elements are parsed in one query. A batch is sent as a literal list
      # of KML fragments, so the ceiling is the size of that statement rather than the
      # element count, and a file of few but very large geometries reaches it first.
      GEOMETRY_BATCH_SIZE = 200

      # matches a coordinate pair with an optional altitude, including invalid altitudes like NaN
      #   -118.1,50.9,NaN
      #   -118.1,50.9,0
      #   -118.1,50.9
      COORDINATES_WITH_ALTITUDE = /(?<lng>\S+),(?<lat>\S+),(?<alt>\S+)/.freeze

      def initialize(data, base_dir: nil, **options)
        @base_dir = base_dir
        super data, **options
      end

      private

      def each_record(&block)
        pending = []

        kml_document.css('Placemark').each do |placemark|
          metadata = extract_metadata(placemark)
          importable_image_paths = images_from_metadata(metadata)
          name = placemark.css('name').text

          geometries_in(placemark).each do |geometry|
            # A hash of its own per feature, since each is stored on a separate record.
            hold(pending, geometry, name, metadata.dup, importable_image_paths, &block)
          end
        end

        kml_document.xpath(UNPLACED_GEOMETRY_XPATH).each do |geometry|
          hold(pending, geometry, nil, {}, [], &block)
        end

        yield_batch(pending, &block)
      end

      # Returns the geometry elements belonging to a Placemark.
      #
      # A Placemark inside another Placemark owns its own geometry, so the outer one has to
      # leave it alone or the same element is read twice. Scoping by depth costs an upward
      # walk per element, which is 7x the plain selector on a document holding six figures
      # of geometry, so it is used only for a document that nests.
      #
      # @param placemark [Nokogiri::XML::Element]
      # @return [Nokogiri::XML::NodeSet] the Polygon, LineString and Point elements whose
      #   nearest enclosing Placemark is this one.
      def geometries_in(placemark)
        return placemark.css(GEOMETRY_SELECTOR) unless nested_placemarks?

        depth = placemark.xpath('count(ancestor::Placemark)').to_i + 1
        placemark.xpath(".//*[#{GEOMETRY_SELF_TEST}][count(ancestor::Placemark) = #{depth}]")
      end

      # Returns true when any Placemark in the document holds another, which KML 2.2 does
      # not allow. Read once per document.
      def nested_placemarks?
        return @nested_placemarks if defined?(@nested_placemarks)

        @nested_placemarks = kml_document.at_xpath('//Placemark//Placemark').present?
      end

      # Yields the feature built from a geometry element.

      # Holds a geometry element until there are enough of them to parse in one query.
      #
      # @param geometry [Nokogiri::XML::Element] a Polygon, LineString or Point node.
      # @param metadata [Hash] stored on the feature as it stands, so it must already have
      #   had its image keys removed.
      # @return [void] an element holding no coordinates is dropped rather than held.
      def hold(pending, geometry, name, metadata, importable_image_paths, &block)
        return if blank_feature?(geometry)

        pending << [geometry, name, metadata, importable_image_paths]
        yield_batch(pending, &block) if pending.size >= GEOMETRY_BATCH_SIZE
      end

      # Yields a feature for each held element, in the order they were held.
      #
      # @yield [OpenStruct] an element PostGIS cannot read yields nothing.
      def yield_batch(pending, &block)
        return if pending.empty?

        geographies = geom_from_kml_batch(pending.map(&:first))

        pending.each_with_index do |(_, name, metadata, importable_image_paths), index|
          geog = geographies[index]
          next if geog.blank?

          block.call OpenStruct.new(geog: geog, name: name, metadata: metadata,
                                    importable_image_paths: importable_image_paths)
        end

        pending.clear
      end

      # Parses many KML geometry elements in one query.
      #
      # @param geometries [Array<Nokogiri::XML::Element>]
      # @return [Array<String, nil>] one geography per element, in the order given, nil
      #   where the element could not be read. A batch holding an element PostGIS rejects
      #   fails as a whole, so it is re-read one element at a time and only that element
      #   is lost.
      def geom_from_kml_batch(geometries)
        return [geom_from_kml(geometries.first)] if geometries.one?

        geometries.each {|geometry| strip_altitude(geometry) }
        connection = ActiveRecord::Base.connection
        values = geometries.each_with_index.map {|geometry, index| "(#{index}, #{connection.quote(geometry.to_s)})" }

        rows = ActiveRecord::Base.transaction(requires_new: true) do
          connection.select_rows(<<~SQL)
            SELECT t.i, ST_GeomFromKML(t.kml)
            FROM (VALUES #{values.join(',')}) AS t(i, kml)
            ORDER BY t.i
          SQL
        end

        rows.map(&:last)
      rescue ActiveRecord::StatementInvalid
        geometries.map {|geometry| geom_from_kml(geometry) }
      end

      def kml_document
        @kml_document ||= begin
          doc = Nokogiri::XML(@data)
          doc.remove_namespaces! # We don't care about namespaces since the document is going to be filled with placemark geometry and we want it all without needing to deal with namespaces
          raise ImportError, "Invalid KML document (root node was '#{doc.root&.name}')" unless doc.root&.name.to_s.casecmp?('kml')
          discard_network_links(doc)
          discard_overlays(doc)
          doc
        end
      end

      # Overlays drape a georeferenced picture over the map — often a WMS raster exported
      # from a government catalogue — instead of describing an area, so there is no
      # geometry in them to import. A PhotoOverlay also carries a `<Point>` marking where
      # the photo was taken, which is not a footprint either, so the nodes are removed
      # rather than left for `each_record` to pick up. Treated like NetworkLinks: any real
      # geometry in the file still imports, and a file that is nothing but overlays fails
      # with a reason that tells the user what they actually uploaded.
      OVERLAY_ELEMENTS = %w[GroundOverlay PhotoOverlay ScreenOverlay].freeze

      def discard_overlays(doc)
        overlays = doc.search(*OVERLAY_ELEMENTS)
        return if overlays.empty?

        names = overlays.map {|overlay| overlay.at_css('name')&.text.presence }.compact.uniq
        described = names.any? ? ": #{names.to_sentence}" : ''
        @warnings << "Skipped #{overlays.size} map #{'image'.pluralize(overlays.size)}#{described}. " \
                     "A map image is a picture laid over the map, not a marked area, so there is no boundary to import from it."

        overlays.remove
      end

      # NetworkLinks reference geometry hosted elsewhere (e.g. a remote KMZ) rather
      # than embedding it, so there is nothing for us to import from them. Rather than
      # failing the whole file, we drop them and record a warning so any embedded
      # geometry still imports and the user is told which layers were skipped. If the
      # file contained nothing but NetworkLinks the import ends up empty and the
      # EmptyImportError surfaces the warning as the reason.
      def discard_network_links(doc)
        network_links = doc.search('NetworkLink')
        return if network_links.empty?

        names = network_links.map {|link| link.at_css('name')&.text.presence }.compact.uniq
        described = names.any? ? ": #{names.to_sentence}" : ''
        @warnings << "Skipped #{network_links.size} network-linked #{'layer'.pluralize(network_links.size)}#{described}. " \
                     "Network links point at data stored somewhere else rather than holding it, so there is nothing to import from them."

        network_links.remove
      end

      def blank_feature?(feature)
        feature.css('coordinates').text.blank?
      end

      def geom_from_kml(kml)
        strip_altitude(kml)

        # Run the parse inside a SAVEPOINT so a `ST_GeomFromKML` failure on a single
        # invalid feature rolls back only that savepoint, not the surrounding
        # transaction. The previous implementation spawned a thread and checked out
        # a fresh connection for the same isolation reason, but on Rails 8 that
        # pattern deadlocks under `use_transactional_fixtures` — the test pins its
        # connection, the spawned thread blocks indefinitely waiting on
        # `ActiveRecord::Base.connection_pool.checkout`. A nested transaction
        # (`requires_new: true`) gives identical fault containment without crossing
        # thread boundaries.
        ActiveRecord::Base.transaction(requires_new: true) do
          conn = ActiveRecord::Base.connection
          conn.select_value("SELECT ST_GeomFromKML(#{conn.quote(kml.to_s)})")
        end
      rescue ActiveRecord::StatementInvalid # Discard invalid KML features
        nil
      end

      def images_from_metadata(metadata)
        IMAGE_METADATA_KEYS.flat_map do |key|
          images = metadata.delete(key)
          next unless images

          Nokogiri::HTML.fragment(images).css("img").map do |img|
            next unless (src = img["src"])
            @base_dir.join(src.downcase)
          end
        end.compact
      end

      def extract_metadata(placemark)
        metadata = {}
        metadata.merge! extract_table(placemark)
        metadata.merge! extract_extended_data(placemark)
        metadata.merge! description: placemark.css('description').text if metadata.empty?
        metadata.delete_if {|key, value| value.blank? }

        return metadata
      end

      def extract_extended_data(placemark)
        metadata = {}
        placemark.css('ExtendedData SimpleData').each do |node|
          metadata[node['name']] = node.text
        end
        return metadata
      end

      def extract_table(placemark)
        metadata = {}
        placemark.css('description').each do |description|
          Nokogiri::XML(description.text).css('html table table td').each_slice(2) do |key, value|
            metadata[key.text] = value ? value.text : ''
          end
        end
        return metadata
      end

      def strip_altitude(kml)
        kml.css('coordinates').each do |coordinates|
          coordinates.content = coordinates.content.gsub(COORDINATES_WITH_ALTITUDE, '\k<lng>,\k<lat>')
        end
      end
    end
  end
end
