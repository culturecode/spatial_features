require 'ostruct'

module SpatialFeatures
  module Importers
    class KML < Base
      private

      def each_record(&block)
        Nokogiri::XML(@data).css('Placemark').each do |placemark|
          name = placemark.css('name').text
          metadata = {:description => placemark.css('description').text}

          {'Polygon' => 'POLYGON', 'LineString' => 'LINE', 'Point' => 'POINT'}.each do |kml_type, sql_type|
            placemark.css(kml_type).each do |placemark|
              yield OpenStruct.new(:feature_type => sql_type, :geog => geom_from_kml(placemark), :name => name, :metadata => metadata)
            end
          end
        end
      end

      def geom_from_kml(kml)
        ActiveRecord::Base.connection.select_value("SELECT ST_GeomFromKML('#{kml}')")
      end
    end
  end
end
