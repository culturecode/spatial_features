require 'ostruct'
require 'digest/md5'

module SpatialFeatures
  module Importers
    class OGR < Base
      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(geojson)
      end

      private

      def each_record(&block)
        JSON.parse(geojson)['features'].each do |record|
          yield OpenStruct.new(
            :feature_type => record['geometry']['type'],
            :geog => SpatialFeatures::Utils.geom_from_json(record['geometry']),
            :metadata => record['properties']
          )
        end
      end

      def geojson
        @geojson ||= esri_json_to_geojson(@data)
      end

      def esri_json_to_geojson(url)
        if URI.parse(url).relative?
          `ogr2ogr -f GeoJSON /dev/stdout "#{url}"` # It is a local file path
        else
          `ogr2ogr -f GeoJSON /dev/stdout "#{url}" OGRGeoJSON`
        end
      end
    end
  end
end
