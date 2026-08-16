require 'digest/md5'
require 'json'
require 'tempfile'
require 'spatial_features/importers/geo_json'

module SpatialFeatures
  module Importers
    class ESRIGeoJSON < GeoJSON
      # How many pages to walk before concluding the endpoint is ignoring `resultOffset` and
      # serving the same features over and over. A service capped at the usual 1000 or 2000
      # features per page would have to hold half a million features to reach this
      # legitimately. Raise it for a layer that genuinely holds more.
      class_attribute :max_pages
      self.max_pages = 500

      def parsed_geojson
        @parsed_geojson ||= JSON.parse(geojson)
      end

      def geojson
        @geojson ||= esri_json_to_geojson(@data)
      end

      private

      # Returns the layer as GeoJSON. A relative path is read from disk; anything else is
      # downloaded first, so OGR is always given a local file.
      #
      # @param path_or_url [String] a local file path, or the URL of an ArcGIS query endpoint.
      # @return [String] a GeoJSON FeatureCollection in EPSG:4326.
      # @note Downloading rather than passing the URL to OGR is what makes an endpoint offering
      #   only HTTPS 1.1 readable. GDAL's curl client gets an empty reply from those servers,
      #   which surfaces as `ERROR 1: Empty reply from server`.
      def esri_json_to_geojson(path_or_url)
        return ogr2ogr_to_geojson(path_or_url) if URI.parse(path_or_url).relative?

        with_downloaded_file(path_or_url) do |path|
          ogr2ogr_to_geojson(path)
        end
      end

      # Returns the GeoJSON OGR reads out of the file at `path`, reprojected to EPSG:4326.
      # OGR selects its driver by inspecting the content, so the file may hold either GeoJSON
      # or ESRI JSON.
      #
      # @note No layer name is passed. OGR names a local file's layer after its basename, and
      #   naming a layer that does not exist fails the read.
      def ogr2ogr_to_geojson(path)
        GDAL.capture('ogr2ogr', '-t_srs', 'EPSG:4326', '-f', 'GeoJSON', '/dev/stdout', path)
      end

      # Downloads the query into a tempfile and yields its path, removing it afterwards.
      def with_downloaded_file(url)
        Tempfile.create(['esri_geojson', '.json']) do |tempfile|
          tempfile.binmode
          download_paginated(url, tempfile)
          tempfile.close
          return yield(tempfile.path)
        end
      end

      # Walks the query's pages with `resultOffset` and writes them to `io` as one collection.
      # ArcGIS endpoints cap each response at the service's `maxRecordCount`, commonly 1000 or
      # 2000 features, and set `exceededTransferLimit` while more results are waiting.
      #
      # @note Raises `SpatialFeatures::ImportError` once `max_pages` requests have been made
      #   and the endpoint still reports more, since a server that ignores `resultOffset`
      #   otherwise repeats its first page until the process runs out of memory.
      def download_paginated(url, io)
        combined = nil
        offset = 0
        pages = 0

        loop do
          page = fetch_page(paginated_url(url, offset))
          page_features = page['features'] || []

          if combined.nil?
            combined = page
          else
            combined['features'].concat(page_features)
          end

          break if page_features.empty? || !exceeded_transfer_limit?(page)

          pages += 1
          if pages >= max_pages
            raise SpatialFeatures::ImportError,
                  "This layer was still reporting more features after #{max_pages} requests. " \
                  "The server may be ignoring the `resultOffset` parameter."
          end

          offset += page_features.length
        end

        if combined
          combined.delete('exceededTransferLimit')
          combined['properties']&.delete('exceededTransferLimit')
          io.write(JSON.dump(combined))
        end
      end

      # Returns one page of the query.
      #
      # @return [Hash] the parsed response body.
      # @raise [SpatialFeatures::ImportError] when the endpoint cannot be reached, or answers
      #   with a body that is not JSON. An endpoint that rejects a query replies with HTML or
      #   an error document, which the parse failure alone does not convey.
      def fetch_page(url)
        body = Download.read(url)
        JSON.parse(body)
      rescue JSON::ParserError
        raise SpatialFeatures::ImportError,
              "This layer did not return map data. The server replied with #{body.to_s[0, 100].inspect}."
      end

      # Returns true while the service reports that more features are waiting. Services set the
      # flag at the top level or under `properties` depending on the response format.
      def exceeded_transfer_limit?(page)
        page['exceededTransferLimit'] || page.dig('properties', 'exceededTransferLimit')
      end

      # Returns `url` with `resultOffset` set to `offset`, replacing any the caller supplied.
      # Returns it unchanged for the first page, so a service that does not paginate is asked
      # exactly what the caller asked for.
      def paginated_url(url, offset)
        return url if offset.zero?

        uri = URI.parse(url)
        params = URI.decode_www_form(uri.query || '')
        params.reject! { |key, _| key == 'resultOffset' }
        params << ['resultOffset', offset.to_s]
        uri.query = URI.encode_www_form(params)
        uri.to_s
      end
    end
  end
end
