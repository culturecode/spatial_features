require 'ostruct'
require 'digest/md5'

module SpatialFeatures
  module Importers
    class GeoJSON < Base
      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(geojson)
      end

      private

      def each_record(&block)
        parsed_geojson.fetch('features', []).each do |record|
          metadata = record['properties'] || {}
          name = metadata.delete('name')
          yield OpenStruct.new(
            :feature_type => record['geometry']['type'],
            :geog => SpatialFeatures::Utils.geom_from_json(record['geometry']),
            :name => name,
            :metadata => metadata
          )
        end
      end

      def parsed_geojson
        @parsed_geojson ||= (@data.is_a?(String) ? JSON.parse(@data) : @data) || {}
      end

      def geojson
        @geojson ||= @data.is_a?(String) ? @data : @data.to_json
      end
    end
  end
end
