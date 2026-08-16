require 'net/http'
require 'open-uri'
require 'openssl'

module SpatialFeatures
  module Download
    REMOTE_URL = %r{\Ahttps?://}i.freeze

    # Seconds to wait for a remote source, applied both to establishing the connection and to
    # each read. Without it a hung server holds an import worker open indefinitely.
    mattr_accessor :timeout
    self.timeout = 60

    # Errors meaning a remote source could not be read at all, as opposed to being read and
    # found unusable. `OpenURI::HTTPError` covers the 4xx and 5xx replies.
    UNREACHABLE_ERRORS = [::OpenURI::HTTPError, ::SocketError, ::SystemCallError,
                          ::Net::OpenTimeout, ::Net::ReadTimeout, ::OpenSSL::SSL::SSLError].freeze

    class << self
      # Returns an open File for `file`, which may be a URL, a path, or a File. The content may
      # be a zipped archive; `::open_each` unwraps one.
      #
      # @raise [SpatialFeatures::ImportError] when a remote source cannot be reached.
      def open(file)
        file = fetch(file)
        file = normalize_file(file) if file.is_a?(StringIO)
        return file
      end

      # Returns the body of `path_or_url` as a String, without writing it to disk.
      #
      # @raise [SpatialFeatures::ImportError] when a remote source cannot be reached.
      def read(path_or_url)
        fetch(path_or_url).read
      end

      # Returns an open File for each source in `path_or_url`, unwrapping an archive when
      # `unzip` is given a pattern its entries can match.
      def open_each(path_or_url, unzip: nil, **unzip_options)
        file = Download.open(path_or_url)
        files = if unzip && Unzip.is_zip?(file)
          find_in_zip(file, find: unzip, **unzip_options)
        else
          [file]
        end

        return files.map { |f| File.open(f) }
      end

      def normalize_file(file)
        Tempfile.new.tap do |temp|
          temp.binmode
          temp.write(file.read)
          temp.rewind
        end
      end

      # Returns the entries of the archive at `file` without extracting them.
      def entries(file)
        file = fetch(file)
        file = normalize_file(file) if file.is_a?(StringIO)
        Unzip.entries(file)
      end

      def find_in_zip(file, find:, **unzip_options)
        Unzip.paths(file, find: find, **unzip_options)
      end

      private

      # Returns an IO for `file`: fetched over the network when it is a remote URL, opened from
      # disk when it is any other String, and left to open itself otherwise.
      #
      # @note A local path goes to `File.open`, never `URI.open`. `URI.open` hands anything
      #   that is not a URL to `Kernel#open`, which runs the name as a command when it begins
      #   with a pipe.
      # @note Timeouts and the unreachable rescue apply only to a remote URL. `URI.open`
      #   rejects the timeouts when handed an already open file, and `Errno::ENOENT` for a
      #   local path is a `SystemCallError` that callers turn into a message for the person who
      #   uploaded the file, without naming the path the server looked in.
      def fetch(file)
        return URI.open(file) unless file.is_a?(String)
        return File.open(file) unless file.match?(REMOTE_URL)

        begin
          URI.open(file, :open_timeout => timeout, :read_timeout => timeout)
        rescue *UNREACHABLE_ERRORS => e
          raise SpatialFeatures::ImportError, "This source could not be reached. #{e.message}"
        end
      end
    end
  end
end
