module SpatialFeatures
  module Unzip
    def self.paths(file_path, find: nil, &block)
      dir = Dir.mktmpdir
      paths = []

      entries(file_path) do |entry|
        path = "#{dir}/#{entry.name}"
        entry.extract(path)
        paths << path
      end

      paths = paths.each(&block) if block_given?
      paths = paths.find {|path| path.include?(find) } if find

      return paths
    end

    def self.names(file_path, &block)
      entries(file_path).collect(&:name).each(&block)
    end

    def self.entries(file_path, &block)
      Zip::File.open(File.path(file_path)).each(&block)
    end

    def self.is_zip?(file)
      zip = file.readline.start_with?('PK')
      file.rewind
      return zip
    end
  end
end
