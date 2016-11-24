require 'open-uri'

module SpatialFeatures
  module Importers
    class File < SimpleDelegator
      def initialize(data, *args)
        file = Download.open(data, unzip: %w(.kml .shp))

        if file.path.end_with? '.kml'
          __setobj__(KMLFile.new(file, *args))

        elsif file.path.end_with? '.shp'
          __setobj__(Shapefile.new(file, *args))

        else
          raise ImportError, "Could not import file. Supported formats are KMZ, KML, and zipped ArcGIS shapefiles"
        end
      end
    end
  end
end
