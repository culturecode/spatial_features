require 'ostruct'

module SpatialFeatures
  module Importers
    class KML < Base
      private

      def each_record(&block)
        Nokogiri::XML(@data).css('Placemark').each do |placemark|
          name = placemark.css('name').text
          metadata = extract_metadata(placemark)

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
        ActiveRecord::Base.connection.select_value("SELECT ST_GeomFromKML(#{ActiveRecord::Base.connection.quote(kml.to_s)})")
      end

      def extract_metadata(placemark)
        metadata = {}
        metadata.merge! extract_table(placemark)
        metadata.merge! extract_extended_data(placemark)
        metadata.merge! :description => placemark.css('description').text if metadata.empty?
        metadata.delete_if {|key, value| value.blank? }

        return metadata
      end

      def extract_extended_data(placemark)
        metadata = {}
        placemark.css('ExtendedData SimpleData').each do |node|
          metadata[node['name']] = node.text
        end
        return metadata
      end

      def extract_table(placemark)
        metadata = {}
        placemark.css('description').each do |description|
          Nokogiri::XML(description.text).css('html table table td').each_slice(2) do |key, value|
            metadata[key.text] = value ? value.text : ''
          end
        end
        return metadata
      end
    end
  end
end
