require 'ostruct'

module SpatialFeatures
  module Importers
    class KML < Base
      # <SimpleData name> keys that may contain <img> tags
      IMAGE_METADATA_KEYS = %w[pdfmaps_photos].freeze

      def initialize(data, base_dir: nil, **options)
        @base_dir = base_dir
        super data, **options
      end

      private

      def each_record(&block)
        {'Polygon' => 'POLYGON', 'LineString' => 'LINE', 'Point' => 'POINT'}.each do |kml_type, sql_type|
          kml_document.css(kml_type).each do |feature|
            if placemark = feature.ancestors('Placemark').first
              name = placemark.css('name').text
              metadata = extract_metadata(placemark)
            else
              metadata = {}
            end

            next if blank_feature?(feature)

            geog = geom_from_kml(feature)
            next if geog.blank?

            importable_image_paths = images_from_metadata(metadata)

            yield OpenStruct.new(:feature_type => sql_type, :geog => geog, :name => name, :metadata => metadata, :importable_image_paths => importable_image_paths)
          end
        end
      end

      def kml_document
        @kml_document ||= begin
          doc = Nokogiri::XML(@data)
          raise ImportError, "Invalid KML document (root node was '#{doc.root&.name}')" unless doc.root&.name.to_s.casecmp?('kml')
          raise ImportError, "NetworkLink elements are not supported" unless doc.search('NetworkLink').empty?
          doc
        end
      end

      def blank_feature?(feature)
        feature.css('coordinates').text.blank?
      end

      def geom_from_kml(kml)
        geom = nil
        conn = nil

        # Do query in a new thread so we use a new connection (if the query fails it will poison the transaction of the current connection)
        #
        # We manually checkout a new connection since Rails re-uses DB connections across threads.
        Thread.new do
          conn = ActiveRecord::Base.connection_pool.checkout
          geom = conn.select_value("SELECT ST_GeomFromKML(#{conn.quote(kml.to_s)})")
        rescue ActiveRecord::StatementInvalid => e # Discard Invalid KML features
          geom = nil
        ensure
          ActiveRecord::Base.connection_pool.checkin(conn) if conn
        end.join

        return geom
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
        metadata.merge! :description => placemark.css('description').text if metadata.empty?
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
    end
  end
end
