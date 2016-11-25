module SpatialFeatures
  module Importers
    class KMLFile < KML
      def initialize(path_or_url, *args)
        super Download.read(path_or_url, unzip: '.kml'), *args

      rescue SocketError, Errno::ECONNREFUSED, OpenURI::HTTPError
        url = URI(path_or_url)
        raise ImportError, "KML server is not responding. Ensure server is running and accessible at #{[url.scheme, "//#{url.host}", url.port].select(&:present?).join(':')}."
      end
    end
  end
end
