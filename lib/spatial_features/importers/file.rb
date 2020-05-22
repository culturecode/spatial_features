require 'open-uri'

module SpatialFeatures
  module Importers
    class File < SimpleDelegator
      def initialize(data, *args)
        begin
          file = Download.open(data, unzip: [/\.kml$/, /\.shp$/], downcase: true)
        rescue Unzip::PathNotFound
          raise ImportError, "Archive did not contain a .kml or .shp file. Supported formats are KMZ, KML, and zipped ArcGIS shapefiles."
        end

        case ::File.extname(file.path.downcase)
        when '.kml'
          __setobj__(KMLFile.new(file, *args))
        when '.shp'
          __setobj__(Shapefile.new(file, *args))
        else
          raise ImportError, "Could not import file. Supported formats are KMZ, KML, and zipped ArcGIS shapefiles"
        end
      end
    end
  end
end
