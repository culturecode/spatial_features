require 'open-uri'

module SpatialFeatures
  module Download
    # file can be a url, path, or file, any of which can return be a zipped archive
    def self.open(file)
      file = URI.open(file)
      file = normalize_file(file) if file.is_a?(StringIO)
      return file
    end

    # file can be a url, path, or file, any of which can return be a zipped archive
    def self.open_each(path_or_url, unzip: nil, **unzip_options)
      file = Download.open(path_or_url)
      files = if unzip && Unzip.is_zip?(file)
        find_in_zip(file, find: unzip, **unzip_options)
      else
        [file]
      end

      return files.map { |f| File.open(f) }
    end

    def self.normalize_file(file)
      Tempfile.new.tap do |temp|
        temp.binmode
        temp.write(file.read)
        temp.rewind
      end
    end

    def self.entries(file)
      file = Kernel.open(file)
      file = normalize_file(file) if file.is_a?(StringIO)
      Unzip.entries(file)
    end

    def self.find_in_zip(file, find:, **unzip_options)
      Unzip.paths(file, :find => find, **unzip_options)
    end
  end
end
