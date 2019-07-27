require 'open-uri'

module SpatialFeatures
  module Importers
    class File < SimpleDelegator
      def initialize(data, *args)
        file = Download.open(data, unzip: [/\.kml$/, /\.shp$/])

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
