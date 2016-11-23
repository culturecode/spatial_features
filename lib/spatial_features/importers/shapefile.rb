require 'tempfile'
require 'rgeo/shapefile'
require 'ostruct'

module SpatialFeatures
  module Importers
    class Shapefile < Base
      private

      def each_record(&block)
        Unzip.paths(@data) do |path|
          next unless path.end_with? '.shp'

          RGeo::Shapefile::Reader.open(path) do |records|
            records.each do |record|
              yield OpenStruct.new(:metadata => record.attributes, :geog => geom_from_text(record.geometry.as_text))
            end
          end
        end
      end

      def geom_from_text(wkt)
        ActiveRecord::Base.connection.select_value("SELECT ST_GeomFromText('#{wkt}')")
      end
    end
  end
end
