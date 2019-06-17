require 'ostruct'

module SpatialFeatures
  module Importers
    class KML < Base
      private

      def each_record(&block)
        Nokogiri::XML(@data).css('Placemark').each do |placemark|
          name = placemark.css('name').text
          metadata = { :description => placemark.css('description').text }
          placemark.css('ExtendedData SimpleData').each do |node|
            metadata[node['name']] = node.text
          end
          metadata.delete_if {|key, value| value.blank? }


          {'Polygon' => 'POLYGON', 'LineString' => 'LINE', 'Point' => 'POINT'}.each do |kml_type, sql_type|
            placemark.css(kml_type).each do |placemark|
              next if blank_placemark?(placemark)

              yield OpenStruct.new(:feature_type => sql_type, :geog => geom_from_kml(placemark), :name => name, :metadata => metadata)
            end
          end
        end
      end

      def blank_placemark?(placemark)
        placemark.css('coordinates').text.blank?
      end

      def geom_from_kml(kml)
        ActiveRecord::Base.connection.select_value("SELECT ST_GeomFromKML(#{ActiveRecord::Base.connection.quote(kml)})")
      end
    end
  end
end
