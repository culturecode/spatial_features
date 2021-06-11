module SpatialFeatures
  module Validation
    # SHP file must come first
    REQUIRED_SHAPEFILE_COMPONENT_EXTENSIONS = %w[shp shx dbf prj].freeze

    # Check if a shapefile archive includes the required component files, otherwise
    # raise an exception.
    #
    # @param [Zip::File] zip_file                 A Zip::File object
    # @param [String] default_proj4_projection    Optional, if supplied we don't raise an exception when we're missing a .PRJ file
    # @param [Boolean] allow_generic_zip_files    When true, we skip validation entirely if the archive does not contain a .SHP file
    def self.validate_shapefile_archive!(zip_file, default_proj4_projection: nil, allow_generic_zip_files: false)
      zip_file_entries = zip_file.entries.each_with_object({}) do |f, obj|
        ext = File.extname(f.name).downcase[1..-1]
        next unless ext

        if ext.casecmp?("shp") && obj.key?(ext)
          raise ::SpatialFeatures::Importers::InvalidShapefileArchive, "Zip files that contain multiple Shapefiles are not supported. Please separate each Shapefile into its own zip file."
        end

        obj[ext] = File.basename(f.name, '.*')
      end

      shapefile_basename = zip_file_entries["shp"]
      unless shapefile_basename
        # not a shapefile archive but we don't care
        return if allow_generic_zip_files

        raise ::SpatialFeatures::Importers::IncompleteShapefileArchive, "Shapefile archive is missing a SHP file"
      end

      REQUIRED_SHAPEFILE_COMPONENT_EXTENSIONS[1..-1].each do |ext|
        ext_basename = zip_file_entries[ext]
        next if ext_basename&.casecmp?(shapefile_basename)

        case ext
        when "prj"
          # special case for missing projection files to allow using default_proj4_projection
          next if default_proj4_projection

          raise ::SpatialFeatures::Importers::IndeterminateShapefileProjection, "Shapefile archive is missing a projection file: #{expected_component_path(shapefile_basename, ext)}"
        else
          # for all un-handled cases of missing files raise the more generic error
          raise ::SpatialFeatures::Importers::IncompleteShapefileArchive, "Shapefile archive is missing a required file: #{expected_component_path(shapefile_basename, ext)}"
        end
      end

      true
    end

    def self.expected_component_path(basename, ext)
      "#{basename}.#{ext}"
    end
  end
end
