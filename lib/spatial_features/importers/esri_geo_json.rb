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
          URI.open(url) { |io| IO.copy_stream(io, tempfile) }
          tempfile.close
          return yield(tempfile.path)
        end
      end
    end
  end
end
