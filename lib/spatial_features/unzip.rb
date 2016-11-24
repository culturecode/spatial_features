module SpatialFeatures
  module Unzip
    def self.paths(file_path, find: nil)
      dir = Dir.mktmpdir
      paths = []

      entries(file_path).each do |entry|
        path = "#{dir}/#{entry.name}"
        entry.extract(path)
        paths << path
      end

      paths = paths.find {|path| path.include?(find) } if find

      return paths
    end

    def self.names(file_path)
      entries(file_path).collect(&:name)
    end

    def self.entries(file_path)
      Zip::File.open(File.path(file_path))
    end

    def self.is_zip?(file)
      zip = file.readline.start_with?('PK')
      file.rewind
      return zip
    end
  end
end
