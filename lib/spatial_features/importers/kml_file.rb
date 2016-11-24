module SpatialFeatures
  module Importers
    class KMLFile < KML
      def initialize(path_or_url, *args)
        super fetch(path_or_url), *args
      end

      private

      def fetch(path_or_url)
        Download.read(path_or_url, unzip: '.kml')
      rescue SocketError, Errno::ECONNREFUSED
        url = URI(path_or_url)
        raise ImportError, "ArcGIS Server is not responding. Ensure ArcGIS Server is running and accessible at #{[url.scheme, "//#{url.host}", url.port].select(&:present?).join(':')}."
      rescue OpenURI::HTTPError
        raise ImportError, "ArcGIS Map Service not found. Ensure ArcGIS Server is running and accessible at #{path_or_url}."
      end
    end

    class ImportError < StandardError; end
  end
end
