require 'digest/md5'

module SpatialFeatures
  module Importers
    # Stands in for a source file we couldn't read at all — an archive with no map data in
    # it, a shapefile missing a component, an unsupported format. It behaves like an
    # importer that found nothing and carries the reason as a warning, so the files
    # uploaded beside it still import and the user is told which file was skipped and why.
    #
    # When every source is unreadable the import ends up empty and `update_features!`
    # raises `EmptyImportError` with these warnings as the reason, the same way a file
    # containing only NetworkLinks does.
    class UnreadableFile < Base
      # Fallback for a failure that didn't come from an importer (a corrupt archive
      # surfacing as a Zip error, say), whose own message would mean nothing to the person
      # who uploaded the file.
      UNREADABLE = "This file couldn't be opened. It may be damaged, or saved in a format we can't read.".freeze

      def initialize(data, error, **options)
        super(data, **options)
        self.source_identifier ||= ::File.basename(data.to_s)
        @warnings << (error.is_a?(ImportError) ? error.message : UNREADABLE)
      end

      # Include the reason so that fixing an importer (or the user re-uploading) produces a
      # different key and the record re-imports rather than matching its cached hash.
      def cache_key
        @cache_key ||= Digest::MD5.hexdigest([@data, *@warnings].join)
      end

      private

      def each_record
        # Nothing could be read, so there is nothing to yield.
      end
    end
  end
end
