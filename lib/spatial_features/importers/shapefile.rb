require 'rgeo/shapefile'
require 'ostruct'

module SpatialFeatures
  module Importers
    class Shapefile < Base

      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(features.to_json)
      end

      private

      def each_record(&block)
        file = Download.open(@data, unzip: '.shp')
        RGeo::Shapefile::Reader.open(file.path) do |records|
          records.each do |record|
            yield OpenStruct.new(:metadata => record.attributes, :geog => geom_from_text(record.geometry.as_text))
          end
        end
      end

      def geom_from_text(wkt)
        ActiveRecord::Base.connection.select_value("SELECT ST_GeomFromText('#{wkt}')")
      end
    end
  end
end
