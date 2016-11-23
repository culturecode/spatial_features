require 'ostruct'

module SpatialFeatures
  module Importers
    class KMLFileArcGIS < KMLFile
      private

      # ArcGIS includes metadata as an html table in the description
      def each_record(&block)
        super do |record|
          record.metadata = Hash[Nokogiri::XML(record.metadata[:description]).css('td').collect(&:text).each_slice(2).to_a]
          yield record
        end
      end
    end
  end
end
