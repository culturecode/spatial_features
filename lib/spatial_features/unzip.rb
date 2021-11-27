require 'fileutils'

module SpatialFeatures
  module Unzip
    # paths containing '__macosx' or beginning with a '.'
    IGNORED_ENTRY_PATHS = /(\A|\/)(__macosx|\.)/i.freeze

    def self.paths(file_path, find: nil, **extract_options)
      paths = extract(file_path, **extract_options)

      if find = Array.wrap(find).presence
        paths = paths.select {|path| find.any? {|pattern| path.index(pattern) } }
        raise(PathNotFound, "Archive did not contain a file matching #{find}") if paths.empty?
      end

      return Array(paths)
    end

    def self.extract(file_path, output_dir = Dir.mktmpdir, downcase: false)
      [].tap do |paths|
        entries(file_path).each do |entry|
          next if entry.name =~ IGNORED_ENTRY_PATHS
          output_filename = entry.name
          output_filename = output_filename.downcase if downcase
          path = "#{output_dir}/#{output_filename}"
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

    # EXCEPTIONS

    class PathNotFound < StandardError; end
  end
end
