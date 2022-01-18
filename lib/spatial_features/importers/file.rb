require 'open-uri'

module SpatialFeatures
  module Importers
    class File < SimpleDelegator
      INVALID_ARCHIVE = "Archive did not contain a .kml, .shp, .json, or .geojson file.".freeze
      SUPPORTED_FORMATS = "Supported formats are KMZ, KML, zipped ArcGIS shapefiles, ESRI JSON, and GeoJSON.".freeze

      FILE_PATTERNS = [/\.kml$/, /\.shp$/, /\.json$/, /\.geojson$/]
      def self.create_all(data, **options)
        Download.open_each(data, unzip: FILE_PATTERNS, downcase: true).map do |file|
          new(data, **options, current_file: file)
        end
      rescue Unzip::PathNotFound
        raise ImportError, INVALID_ARCHIVE + " " + SUPPORTED_FORMATS
      end

      # The File importer may be initialized multiple times by `::create_all` if it
      # receives ZIP data containing multiple KML or SHP files. We use `current_file`
      # to distinguish which file in the archive is currently being
      # processed.
      #
      # If no `current_file` is passed then we just take the first valid file that we find.
      def initialize(data, *args, current_file: nil, **options)
        begin
          current_file ||= Download.open_each(data, unzip: FILE_PATTERNS, downcase: true).first
        rescue Unzip::PathNotFound
          raise ImportError, INVALID_ARCHIVE
        end

        case ::File.extname(current_file.path.downcase)
        when '.kml'
          __setobj__(KMLFile.new(current_file, *args, **options))
        when '.shp'
          __setobj__(Shapefile.new(current_file, *args, **options))
        when '.json', '.geojson'
          __setobj__(ESRIGeoJSON.new(current_file.path, *args, **options))
        else
          raise ImportError, "Could not import file. " + SUPPORTED_FORMATS
        end
      end
    end
  end
end
