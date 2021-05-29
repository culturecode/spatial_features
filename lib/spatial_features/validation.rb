module SpatialFeatures
  module Validation
    # SHP file must come first
    REQUIRED_SHAPEFILE_COMPONENT_EXTENSIONS = %w[shp shx dbf prj].freeze

    # Check if a shapefile archive includes the required component files, otherwise
    # raise an exception.
    #
    # @param [String] file_path                   Path of the zip archive
    # @param [Zip::File] zip_file                 A Zip::File object
    # @param [String] default_proj4_projection    Optional, if supplied we don't raise an exception when we're missing a .PRJ file
    # @param [Boolean] allow_generic_zip_files    When true, we skip validation entirely if the archive does not contain a .SHP file
    def self.validate_shapefile_archive!(archive_path, zip_file, default_proj4_projection: nil, allow_generic_zip_files: false)
      archive_component_extensions = zip_file.entries.map { |f| File.extname(f.name.downcase) }
      REQUIRED_SHAPEFILE_COMPONENT_EXTENSIONS.each do |ext|
        next if archive_component_extensions.include? ".#{ext}"

        case ext
        when "shp"
          return if allow_generic_zip_files

        when "prj"
          # special case for missing projection files to allow using default_proj4_projection
          if default_proj4_projection
            next
          else
            raise ::SpatialFeatures::Importers::IndeterminateShapefileProjection, "Shapefile archive is missing a projection file: #{expected_component_path(archive_path, ext)}"
          end
        end

        # for all un-handled cases of missing files raise the more generic error
        raise ::SpatialFeatures::Importers::IncompleteShapefileArchive, "Shapefile archive is missing a required file: #{expected_component_path(archive_path, ext)}"
      end

      true
    end

    def self.expected_component_path(archive_path, ext)
      "#{::File.basename(archive_path, '.*')}.#{ext}"
    end
  end
end
