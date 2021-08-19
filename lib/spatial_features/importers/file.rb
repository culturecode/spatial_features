require 'open-uri'

module SpatialFeatures
  module Importers
    class File < SimpleDelegator
      INVALID_ARCHIVE = "Archive did not contain a .kml or .shp file. Supported formats are KMZ, KML, and zipped ArcGIS shapefiles.".freeze

      def initialize(data, *args, **options)
        # the current_file param is passed by `::create` after it has opened a zip
        # archive and extracted the KML and SHP files
        current_file = options.delete(:current_file)

        begin
          current_file ||= Download.open_each(data, unzip: [/\.kml$/, /\.shp$/], downcase: true).first
        rescue Unzip::PathNotFound
          raise ImportError, INVALID_ARCHIVE
        end

        case ::File.extname(current_file.path.downcase)
        when '.kml'
          __setobj__(KMLFile.new(current_file, *args))
        when '.shp'
          __setobj__(
            Shapefile.new(data, *args, **options, shp_file_name: ::File.basename(current_file&.path))
          )
        else
          raise ImportError, "Could not import file. Supported formats are KMZ, KML, and zipped ArcGIS shapefiles"
        end
      end

      # DO we want to pass the zip back down
      def self.create(data, **options)
        # explode open then build multiple File
        Download.open_each(data, unzip: [/\.kml$/, /\.shp$/], downcase: true).map do |file|
          new(data, **options, current_file: file)
        end
      rescue Unzip::PathNotFound
        raise ImportError, INVALID_ARCHIVE
      end
    end
  end
end
