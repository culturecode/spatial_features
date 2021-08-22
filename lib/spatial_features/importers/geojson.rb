require 'ostruct'
require 'digest/md5'

module SpatialFeatures
  module Importers
    class GeoJSON < Base
      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(features.to_json)
      end

      private

      def each_record(&block)
        return unless @data

        @data.fetch('features', []).each do |record|
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
    end
  end
end
