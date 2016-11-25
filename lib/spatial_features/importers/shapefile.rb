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
        proj4 = proj4_from_file(file)
        RGeo::Shapefile::Reader.open(file.path) do |records|
          records.each do |record|
            yield OpenStruct.new data_from_wkt(record.geometry.as_text, proj4).merge(:metadata => record.attributes)
          end
        end
      end

      def proj4_from_file(file)
        `gdalsrsinfo "#{file.path}" -o proj4`[/'(.+)'/,1] # Sanitize "'+proj=utm +zone=11 +datum=NAD83 +units=m +no_defs '\n"
      end

      def data_from_wkt(wkt, proj4)
        ActiveRecord::Base.connection.select_one <<-SQL
          SELECT ST_Transform(ST_GeomFromText('#{wkt}'), '#{proj4}', 4326) AS geog, GeometryType(ST_GeomFromText('#{wkt}')) AS feature_type
        SQL
      end
    end
  end
end
