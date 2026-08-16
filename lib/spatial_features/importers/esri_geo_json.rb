require 'digest/md5'
require 'open3'
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

      def esri_json_to_geojson(url)
        args = ['ogr2ogr', '-t_srs', 'EPSG:4326', '-f', 'GeoJSON', '/dev/stdout', url]
        args << 'OGRGeoJSON' unless URI.parse(url).relative? # A relative URL is a local file path
        Open3.capture2(*args).first
      end
    end
  end
end
