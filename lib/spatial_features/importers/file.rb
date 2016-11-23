module SpatialFeatures
  module Importers
    class File < SimpleDelegator
      def initialize(data, *args)
        names = Unzip.names(data)
        if names.any? {|name| name.ends_with? '.kml' }
          __setobj__(KmlFile.new(data, *args))

        elsif names.any? {|name| name.ends_with? '.shp' }
          __setobj__(Shapefile.new(data, *args))

        else
          raise "Could not detect importer for file"
        end
      end
    end
  end
end
