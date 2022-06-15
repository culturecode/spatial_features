require 'ostruct'

module SpatialFeatures
  module Importers
    class KMLFileArcGIS < KMLFile
      def initialize(data, **options)
        super

      rescue SocketError, Errno::ECONNREFUSED
        url = URI(data)
        raise ImportError, "ArcGIS Server is not responding. Ensure ArcGIS Server is running and accessible at #{[url.scheme, "//#{url.host}", url.port].select(&:present?).join(':')}."
      rescue OpenURI::HTTPError
        raise ImportError, "ArcGIS Map Service not found. Ensure ArcGIS Server is running and accessible at #{path_or_url}."
      end

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
