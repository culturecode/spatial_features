require 'open-uri'

module SpatialFeatures
  module Download
    # file can be a url, path, or file, any of which can return be a zipped archive
    def self.read(file, unzip: nil, **unzip_options)
      file = open(file, unzip: unzip, **unzip_options)
      path = ::File.path(file)
      return ::File.read(path)
    end

    def self.open(file, unzip: nil, **unzip_options)
      file = Kernel.open(file)
      file = normalize_file(file) if file.is_a?(StringIO)
      if unzip && Unzip.is_zip?(file)
        file = find_in_zip(file, find: unzip, **unzip_options)
      end
      return file
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
      return File.open(Unzip.paths(file, :find => find, **unzip_options))
    end
  end
end
