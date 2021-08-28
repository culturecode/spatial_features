module SpatialFeatures
  module Validation
    REQUIRED_SHAPEFILE_COMPONENT_EXTENSIONS = %w[shx dbf prj].freeze

    class << self
      # Check if a shapefile includes the required component files, otherwise
      # raise an exception.
      #
      # This validation operates by checking sibling files in the same directory,
      # similar to how `rgeo-shapefile` validates SHP  files.
      #
      # @param [File] shp_file                      A File object
      # @param [String] default_proj4_projection    Optional, if supplied we don't raise an exception when we're missing a .PRJ file
      def validate_shapefile!(shp_file, default_proj4_projection: nil)
        basename = File.basename(shp_file.path, '.*')
        path = shp_file.path.to_s.sub(/\.shp$/i, "")

        required_extensions = REQUIRED_SHAPEFILE_COMPONENT_EXTENSIONS
        required_extensions -= ['prj'] if default_proj4_projection

        required_extensions.each do |ext|
          component_path = "#{path}.#{ext}"
          next if ::File.file?(component_path) && ::File.readable?(component_path)

          case ext
            when "prj"
              raise ::SpatialFeatures::Importers::IndeterminateShapefileProjection, "Shapefile archive is missing a projection file: #{File.basename(component_path)}"
            else
              raise ::SpatialFeatures::Importers::IncompleteShapefileArchive, "Shapefile archive is missing a required file: #{File.basename(component_path)}"
            end
        end

        true
      end
    end
  end
end
