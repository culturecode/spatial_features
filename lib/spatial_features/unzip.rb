require 'fileutils'
require 'pathname'

module SpatialFeatures
  module Unzip
    # paths containing '__macosx' or beginning with a '.'
    IGNORED_ENTRY_PATHS = /(\A|\/)(__macosx|\.)/i.freeze

    # Archives that may themselves hold the file we're looking for. A KMZ is a ZIP with a
    # KML inside it, and proponents routinely forward a ZIP of per-layer ZIPs rather than
    # the layers themselves.
    NESTED_ARCHIVE_PATTERN = /\.(zip|kmz)$/i.freeze

    # How many times we'll unwrap a nested archive before giving up. Two levels covers
    # every case we've seen in practice (a ZIP of shapefile ZIPs, a ZIP holding a KMZ)
    # while bounding the work a deeply nested archive can cost us.
    MAX_NESTING_DEPTH = 2

    def self.paths(file_path, find: nil, depth: 0, **extract_options)
      paths = extract(file_path, **extract_options)

      if find = Array.wrap(find).presence
        matches = matching_paths(paths, find)
        # Only unwrap nested archives once the archive has yielded nothing usable, so
        # archives that already import keep their current behaviour exactly.
        matches = paths_in_nested_archives(paths, find: find, depth: depth, **extract_options) if matches.empty?
        raise(PathNotFound.new("Archive did not contain a file matching #{find}", paths)) if matches.empty?
        paths = matches
      end

      return Array(paths)
    end

    def self.matching_paths(paths, find)
      paths.select {|path| find.any? {|pattern| path.index(pattern) } }
    end

    # Unwrap any archives the archive itself contained and search those instead. Each one
    # extracts into its own directory so identically named entries (`doc.kml` in several
    # KMZs) don't overwrite one another, and so a shapefile's sibling components stay
    # beside it for `Validation.validate_shapefile!`.
    def self.paths_in_nested_archives(paths, find:, depth:, tmpdir: nil, **extract_options)
      return [] unless depth < MAX_NESTING_DEPTH

      paths.grep(NESTED_ARCHIVE_PATTERN).flat_map do |archive|
        begin
          paths(archive, find: find, depth: depth + 1,
                         tmpdir: Dir.mktmpdir(nil, File.dirname(archive)), **extract_options)
        rescue PathNotFound, Zip::Error
          [] # This nested archive held nothing we can use; the others may still.
        end
      end
    end

    # Extracts the archive's entries and returns their paths, skipping entries that a name
    # cannot place inside `tmpdir`.
    #
    # @param tmpdir [String] where to extract to. Must already exist, since the destination
    #   is resolved before anything is written. Defaults to a fresh temporary directory.
    def self.extract(file_path, tmpdir: nil, downcase: false)
      tmpdir ||= Dir.mktmpdir
      root = Pathname.new(tmpdir).realpath

      [].tap do |paths|
        entries(file_path).each do |entry|
          next if entry.name =~ IGNORED_ENTRY_PATHS
          next if entry.symlink?

          output_filename = entry.name
          output_filename = output_filename.downcase if downcase

          path = contained_path(root, output_filename)
          next unless path

          directory = File.dirname(path)
          basename = File.basename(path)

          FileUtils.mkdir_p(directory)
          entry.extract(basename, destination_directory: directory)

          paths << path
        end
      end
    end

    # Returns where an entry of this name lands under `root`, or nil when the name would place
    # it outside. Entry names are stored in the archive verbatim, so they can carry `..`
    # segments that climb out of the directory we extract into.
    #
    # @note `root` must already be a real path, and `::extract` skips symlink entries, so
    #   nothing beneath it is a symlink. `cleanpath` resolves `..` lexically, so a symlink
    #   under `root` would let an entry name walk back out of the directory unnoticed.
    def self.contained_path(root, output_filename)
      path = root.join(output_filename).cleanpath

      return unless path.to_s.start_with?("#{root}#{File::SEPARATOR}")

      # `cleanpath` drops the trailing separator that marks a directory entry, which
      # `PathNotFound#extensions` reads to tell directories from the files it reports.
      output_filename.end_with?(File::SEPARATOR) ? "#{path}#{File::SEPARATOR}" : path.to_s
    end
    private_class_method :contained_path

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

    class PathNotFound < StandardError
      # The paths the archive did contain, so callers can tell the user what we found
      # instead of only what we needed.
      attr_reader :paths

      def initialize(message = nil, paths = [])
        super(message)
        @paths = Array(paths)
      end

      # Distinct file types in the archive, upcased for display (e.g. `["PDF", "PNG"]`).
      def extensions
        paths.reject {|path| path.end_with?('/') }
             .map {|path| File.extname(path).delete('.').upcase }
             .reject(&:empty?)
             .uniq
             .sort
      end
    end
  end
end
