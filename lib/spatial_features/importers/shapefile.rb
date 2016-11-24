require 'tempfile'
require 'rgeo/shapefile'
require 'ostruct'

module SpatialFeatures
  module Importers
    class Shapefile < Base
      private

      def each_record(&block)
        RGeo::Shapefile::Reader.open(unzip(@data)) do |records|
          records.each do |record|
            yield OpenStruct.new(:metadata => record.attributes, :geog => geom_from_text(record.geometry.as_text))
          end
        end
      end

      def geom_from_text(wkt)
        ActiveRecord::Base.connection.select_value("SELECT ST_GeomFromText('#{wkt}')")
      end

      def unzip(file)
        path = ::File.path(file)
        path = Unzip.paths(file, :find => '.shp') || raise(ImportError, "File missing SHP") if path.end_with?('.zip')
        return path
      end
    end
  end
end
