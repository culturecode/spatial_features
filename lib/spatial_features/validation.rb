module SpatialFeatures
  module Validation
    REQUIRED_SHAPEFILE_COMPONENT_EXTENSIONS = %w[shp shx dbf prj].freeze

    class << self
      # Check if a shapefile archive includes the required component files, otherwise
      # raise an exception.
      #
      # @param [Zip::File] zip_file                 A Zip::File object
      # @param [String] default_proj4_projection    Optional, if supplied we don't raise an exception when we're missing a .PRJ file
      # @param [Boolean] allow_generic_zip_files    When true, we skip validation entirely if the archive does not contain a .SHP file
      def validate_shapefile_archive!(zip_file, default_proj4_projection: nil, allow_generic_zip_files: false)
        contains_shp_file = false

        zip_file_basenames = shapefiles_with_components(zip_file)

        if zip_file_basenames.empty?
          return if allow_generic_zip_files
          raise ::SpatialFeatures::Importers::IncompleteShapefileArchive, "Shapefile archive is missing a SHP file"
        end

        zip_file_basenames.each do |basename, extensions|
          validate_components_for_basename(basename, extensions, default_proj4_projection)
        end

        true
      end

      def shapefiles_with_components(zip_file)
        zip_file.entries.each_with_object({}) do |f, obj|
          filename = f.name

          basename = File.basename(filename, '.*')
          ext = File.extname(filename).downcase[1..-1]
          next unless ext

          obj[basename] ||= []
          obj[basename] << ext
        end.delete_if { |basename, exts| !exts.include?("shp") }
      end

      def validate_components_for_basename(basename, extensions, has_default_proj4_projection)
        required_extensions = REQUIRED_SHAPEFILE_COMPONENT_EXTENSIONS
        required_extensions -= ['prj'] if has_default_proj4_projection
        missing_extensions = required_extensions - extensions

        missing_extensions.each do |ext|
          case ext
            when "prj"
              raise ::SpatialFeatures::Importers::IndeterminateShapefileProjection, "Shapefile archive is missing a projection file: #{expected_component_path(basename, ext)}"
            else
              raise ::SpatialFeatures::Importers::IncompleteShapefileArchive, "Shapefile archive is missing a required file: #{expected_component_path(basename, ext)}"
            end
        end
      end

      def expected_component_path(basename, ext)
        "#{basename}.#{ext}"
      end
    end
  end
end
