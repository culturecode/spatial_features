module SpatialFeatures
  module Importers
    class KMLFile < KML
      def initialize(path_or_url, **options)
        path = Download.open_each(path_or_url, unzip: [/\.kml$/], downcase: true).first
        super ::File.read(path), base_dir: Pathname.new(path).dirname, **options
      rescue SocketError, Errno::ECONNREFUSED, OpenURI::HTTPError
        url = URI(path_or_url)
        raise ImportError, "KML server is not responding. Ensure server is running and accessible at #{[url.scheme, "//#{url.host}", url.port].select(&:present?).join(':')}."
      end

      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(@data)
      end
    end
  end
end
