module SpatialFeatures
  module Unzip
    def self.paths(file_path, &block)
      Dir.mktmpdir do |dir|
        files = []

        entries(file_path) do |entry|
          path = "#{dir}/#{entry.name}"
          entry.extract(path)
          files << path
        end

        files.each(&block)
      end
    end

    def self.names(file_path, &block)
      entries(file_path).collect(&:name).each(&block)
    end

    def self.entries(file_path, &block)
      path = File.path(file_path)
      name = File.basename(file_path)

      if name.end_with?('.zip')
        Zip::File.open(path).each(&block)
      else
        [Zip::Entry.new(path, name)].each(&block)
      end
    end
  end
end
