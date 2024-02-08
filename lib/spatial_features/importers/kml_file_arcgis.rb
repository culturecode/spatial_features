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
    end
  end
end
