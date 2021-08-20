require 'open-uri'

module SpatialFeatures
  module Importers
    class File < SimpleDelegator
      INVALID_ARCHIVE = "Archive did not contain a .kml or .shp file. Supported formats are KMZ, KML, and zipped ArcGIS shapefiles.".freeze

      def self.create_all(data, **options)
        Download.open_each(data, unzip: [/\.kml$/, /\.shp$/], downcase: true).map do |file|
          new(data, **options, current_file: file)
        end
      rescue Unzip::PathNotFound
        raise ImportError, INVALID_ARCHIVE
      end


      # The File importer may be initialized multiple times by `::create_all` if it
      # receives ZIP data containinng multiple KML and SHP files
      #
      # We use `current_file` to distinguish which file in the archive is currently being
      # processed. If no `current_file` is passed then we just take the first valid
      # file that we find.
      def initialize(data, *args, current_file: nil, **options)
        begin
          current_file ||= Download.open_each(data, unzip: [/\.kml$/, /\.shp$/], downcase: true).first
        rescue Unzip::PathNotFound
          raise ImportError, INVALID_ARCHIVE
        end

        case ::File.extname(current_file.path.downcase)
        when '.kml'
          __setobj__(KMLFile.new(current_file, *args))
        when '.shp'
          # We pass the raw `data` to Importers::Shapefile so it can re-examine any
          # ZIP archives and see any related SHX, DBF and PRJ files
          __setobj__(
            Shapefile.new(data, *args, **options, shp_file_name: ::File.basename(current_file&.path))
          )
        else
          raise ImportError, "Could not import file. Supported formats are KMZ, KML, and zipped ArcGIS shapefiles"
        end
      end
    end
  end
end
