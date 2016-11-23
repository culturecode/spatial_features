require 'open-uri'

module SpatialFeatures
  module Importers
    class KMLFile < KML
      def initialize(path_or_url, *args)
        super unzip(fetch(path_or_url)), *args
      end

      private

      def fetch(path_or_url)
        open(path_or_url)
      rescue SocketError, Errno::ECONNREFUSED
        url = URI(path_or_url)
        raise UpdateError, "ArcGIS Server is not responding. Ensure ArcGIS Server is running and accessible at #{[url.scheme, "//#{url.host}", url.port].select(&:present?).join(':')}."
      rescue OpenURI::HTTPError
        raise UpdateError, "ArcGIS Map Service not found. Ensure ArcGIS Server is running and accessible at #{path_or_url}."
      end

      def unzip(file)
        path = ::File.path(file)
        path = Unzip.paths(file, :find => '.kml') || raise(UpdateError, "File missing KML") if path.end_with?('.kmz')
        return ::File.read(path)
      end
    end

    class UpdateError < StandardError; end
  end
end
