module SpatialFeatures
  module Validation
    REQUIRED_SHAPEFILE_COMPONENT_EXTENSIONS = %w[shp shx dbf prj].freeze

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

      # Validation helper that takes examines an entire ZIP file
      #
      # Useful for validating before persisting records but not used internally
      def validate_shapefile_archive!(path, default_proj4_projection: nil, allow_generic_zip_files: false)
        Download.open_each(path, unzip: /\.shp$/, downcase: true).each do |shp_file|
          validate_shapefile!(shp_file, default_proj4_projection: default_proj4_projection)
        end
      rescue Unzip::PathNotFound
        raise ::SpatialFeatures::Importers::IncompleteShapefileArchive, "Shapefile archive is missing a SHP file" \
          unless allow_generic_zip_files
      end
    end
  end
end
