require 'open-uri'

module SpatialFeatures
  module Download
    # file can be a url, path, or file, any of which can return be a zipped archive
    def self.read(file, unzip: nil)
      file = open(file, unzip: unzip)
      path = ::File.path(file)
      return ::File.read(path)
    end

    def self.open(file, unzip: nil)
      file = Kernel.open(file)
      file = normalize_file(file) if file.is_a?(StringIO)
      file = find_in_zip(file, unzip) if Unzip.is_zip?(file)
      return file
    end

    def self.normalize_file(file)
      Tempfile.new.tap do |temp|
        temp.binmode
        temp.write(file.read)
        temp.rewind
      end
    end

    def self.find_in_zip(file, unzip)
      raise "Must specify an :unzip option if opening a zip file. e.g. open(file, :find => '.shp')" unless unzip
      return File.open(Unzip.paths(file, :find => unzip))
    end
  end
end
