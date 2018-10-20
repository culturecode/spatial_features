require 'fileutils'

module SpatialFeatures
  module Unzip
    def self.paths(file_path, find: nil)
      paths = extract(file_path)

      if find = Array.wrap(find).presence
        paths = paths.detect {|path| find.any? {|pattern| path.include?(pattern) } }
        raise(ImportError, "No file matched #{find}") unless paths.present?
      end

      return paths
    end

    def self.extract(file_path, output_dir = Dir.mktmpdir)
      [].tap do |paths|
        entries(file_path).each do |entry|
          path = "#{output_dir}/#{entry.name}"
          FileUtils.mkdir_p(File.dirname(path))
          entry.extract(path)
          paths << path
        end
      end
    rescue => e
      FileUtils.remove_entry(output_dir)
      raise(e)
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
    rescue EOFError
      return false
    end
  end
end
