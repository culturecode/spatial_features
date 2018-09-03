require 'ostruct'
require 'digest/md5'

module SpatialFeatures
  module Importers
    class JsonArcGIS < Base
      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(features.to_json)
      end

      private

      def each_record(&block)
        json = esri_json_to_geojson(@data)
        json['features'].each do |record|
          yield OpenStruct.new(
            :feature_type => record['geometry']['type'],
            :geog => geom_from_json(record['geometry']),
            :metadata => record['properties']
          )
        end
      end

      def esri_json_to_geojson(url)
        JSON.parse(`ogr2ogr -f GeoJSON /dev/stdout "#{url}" OGRGeoJSON`)
      end

      def geom_from_json(geometry)
        ActiveRecord::Base.connection.select_value("SELECT ST_GeomFromGeoJSON('#{geometry.to_json}')")
      end
    end
  end
end
