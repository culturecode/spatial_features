require 'open3'

module SpatialFeatures
  # Runs the GDAL command line tools.
  #
  # Every argument reaches the tool as a single argv entry, so a path or a projection taken
  # from an uploaded archive arrives as one string rather than as shell syntax.
  module GDAL
    class << self
      # Returns what `tool` wrote to standard output.
      #
      # @param tool [String] the executable name, such as `ogr2ogr`.
      # @param args [Array<String>] one argv entry each.
      # @return [String] the output, empty when the tool wrote nothing.
      # @raise [Errno::ENOENT] when the tool is not installed.
      def capture(tool, *args)
        Open3.capture2(*argv(tool, args)).first
      end

      # Runs `tool` for its exit status rather than its output.
      #
      # @param tool [String] the executable name, such as `ogr2ogr`.
      # @param args [Array<String>] one argv entry each.
      # @return [Boolean] true when the tool exited successfully.
      # @raise [Errno::ENOENT] when the tool is not installed.
      def run(tool, *args)
        system(*argv(tool, args))
      end

      private

      # Returns the argv to spawn `tool` with.
      #
      # @note The command is a two element array so that Ruby spawns the executable directly.
      #   Both `system` and `Open3` fall back to a shell when handed a lone string, which
      #   would put every argument here back in reach of shell parsing.
      def argv(tool, args)
        [[tool.to_s, tool.to_s], *args.map(&:to_s)]
      end
    end
  end
end
