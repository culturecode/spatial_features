require 'open-uri'

module SpatialFeatures
  module Importers
    class KMLFile < KML
      def initialize(path_or_url, *args)
        super unzip(fetch(path_or_url)), *args
      end

      private

      def fetch(path_or_url)
        normalize_file(open(path_or_url))
      rescue SocketError, Errno::ECONNREFUSED
        url = URI(path_or_url)
        raise ImportError, "ArcGIS Server is not responding. Ensure ArcGIS Server is running and accessible at #{[url.scheme, "//#{url.host}", url.port].select(&:present?).join(':')}."
      rescue OpenURI::HTTPError
        raise ImportError, "ArcGIS Map Service not found. Ensure ArcGIS Server is running and accessible at #{path_or_url}."
      end

      def unzip(file)
        path = ::File.path(file)
        path = Unzip.paths(file, :find => '.kml') || raise(ImportError, "File missing KML") if Unzip.is_zip?(file)
        return ::File.read(path)
      end

      def normalize_file(file)
        case file
        when StringIO
          Tempfile.new.tap do |f|
            f.binmode
            f.write(file.read)
            f.rewind
          end
        else
          file
        end
      end
    end

    class ImportError < StandardError; end
  end
end
