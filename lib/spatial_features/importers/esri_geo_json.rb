require 'ostruct'
require 'digest/md5'
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
        if URI.parse(url).relative?
          `ogr2ogr -t_srs EPSG:4326 -f GeoJSON /dev/stdout "#{url}"` # It is a local file path
        else
          `ogr2ogr -t_srs EPSG:4326 -f GeoJSON /dev/stdout "#{url}" OGRGeoJSON`
        end
      end
    end
  end
end
