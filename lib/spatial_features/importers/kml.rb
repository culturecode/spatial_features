require 'ostruct'

module SpatialFeatures
  module Importers
    class KML < Base
      private

      def each_record(&block)
        {'Polygon' => 'POLYGON', 'LineString' => 'LINE', 'Point' => 'POINT'}.each do |kml_type, sql_type|
          Nokogiri::XML(@data).css(kml_type).each do |feature|
            if placemark = feature.ancestors('Placemark').first
              name = placemark.css('name').text
              metadata = extract_metadata(placemark)
            else
              metadata = {}
            end

            next if blank_feature?(feature)

            geog = geom_from_kml(feature)

            next if geog.blank?

            yield OpenStruct.new(:feature_type => sql_type, :geog => geog, :name => name, :metadata => metadata)
          end
        end
      end

      def blank_feature?(feature)
        feature.css('coordinates').text.blank?
      end

      def geom_from_kml(kml)
        geom = nil

        # Do query in a new thread so we use a new connection (if the query fails it will poison the transaction of the current connection)
        Thread.new do
          geom = ActiveRecord::Base.connection.select_value("SELECT ST_GeomFromKML(#{ActiveRecord::Base.connection.quote(kml.to_s)})")
        rescue ActiveRecord::StatementInvalid => e # Discard Invalid KML features
          geom = nil
        end.join

        return geom
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
