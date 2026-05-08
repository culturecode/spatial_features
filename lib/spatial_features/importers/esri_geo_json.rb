require 'digest/md5'
require 'open3'
require 'open-uri'
require 'tempfile'
require 'spatial_features/importers/geo_json'

module SpatialFeatures
  module Importers
    class ESRIGeoJSON < GeoJSON
      def parsed_geojson
        @parsed_geojson ||= JSON.parse(geojson)
      end

      def geojson
        @geojson ||= esri_json_to_geojson(@data)
      end

      private

      def esri_json_to_geojson(path_or_url)
        return ogr2ogr_to_geojson(path_or_url) if URI.parse(path_or_url).relative? # It is a local file path

        # Download the URL ourselves rather than letting GDAL's curl fetch it. Servers that only
        # offer HTTPS 1.1 may cause GDAL's curl to fail, but Ruby's open-uri can handle them.
        with_downloaded_file(path_or_url) do |path|
          ogr2ogr_to_geojson(path)
        end
      end

      # Returns the GeoJSON OGR reads out of the file at `path`, reprojected to EPSG:4326.
      def ogr2ogr_to_geojson(path)
        Open3.capture2('ogr2ogr', '-t_srs', 'EPSG:4326', '-f', 'GeoJSON', '/dev/stdout', path).first
      end

      def with_downloaded_file(url)
        Tempfile.create(['esri_geojson', '.json']) do |tempfile|
          tempfile.binmode
          download_paginated(url, tempfile)
          tempfile.close
          return yield(tempfile.path)
        end
      end

      # ArcGIS query endpoints cap each response at the service's maxRecordCount
      # (commonly 1000 or 2000 features) and signal exceededTransferLimit when
      # more results are available. Walk the pages with resultOffset and merge
      # them into a single FeatureCollection before handing to ogr2ogr.
      def download_paginated(url, io)
        combined = nil
        offset = 0

        loop do
          page = JSON.parse(URI.open(paginated_url(url, offset)).read)
          page_features = page['features'] || []

          if combined.nil?
            combined = page
          else
            combined['features'].concat(page_features)
          end

          break if page_features.empty? || !exceeded_transfer_limit?(page)
          offset += page_features.length
        end

        combined&.delete('exceededTransferLimit')
        combined&.fetch('properties', {})&.delete('exceededTransferLimit')
        io.write(JSON.dump(combined)) if combined
      end

      def exceeded_transfer_limit?(page)
        page['exceededTransferLimit'] || page.dig('properties', 'exceededTransferLimit')
      end

      def paginated_url(url, offset)
        return url if offset.zero?
        uri = URI.parse(url)
        params = URI.decode_www_form(uri.query || '')
        params.reject! { |k, _| k == 'resultOffset' }
        params << ['resultOffset', offset.to_s]
        uri.query = URI.encode_www_form(params)
        uri.to_s
      end
    end
  end
end
