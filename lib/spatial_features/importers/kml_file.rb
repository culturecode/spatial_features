require 'open-uri'

module SpatialFeatures
  module Importers
    class KmlFile < Kml
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
        Unzip.paths(file) do |path|
          return ::File.read(path) if path.end_with? '.kml'
        end

        raise UpdateError, "No kml found in file"
      end
    end

    class UpdateError < StandardError; end
  end
end
