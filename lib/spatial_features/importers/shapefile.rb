require 'ostruct'
require 'digest/md5'

module SpatialFeatures
  module Importers
    class Shapefile < Base
      class_attribute :default_proj4_projection

      FEATURE_TYPE_FOR_DIMENSION = { 0 => 'point', 1 => 'line', 2 => 'polygon' }.freeze
      PROJ4_4326 = '+proj=longlat +datum=WGS84 +no_defs'.freeze

      def initialize(data, proj4: nil, **options)
        super(data, **options)
        @proj4 = proj4
      end

      def cache_key
        @cache_key ||= Digest::MD5.file(archive).to_s
      end

      def self.create_all(data, **options)
        Download.open_each(data, unzip: [/\.shp$/], downcase: true).map do |file|
          new(file, **options)
        end
      rescue Unzip::PathNotFound
        raise ImportError, INVALID_ARCHIVE
      end

      private

      def each_record
        open_shapefile(archive) do |records, proj4|
          records.each do |record|
            yield OpenStruct.new data_from_record(record, proj4) if record.geometry.present?
          end
        end
      rescue Errno::ENOENT => e
        case e.message
        when /No such file or directory @ rb_sysopen - (.+)/
          raise IncompleteShapefileArchive, "Shapefile archive is missing a required file: #{::File.basename($1)}"
        else
          raise e
        end
      end

      def data_from_record(record, proj4 = nil)
        geometry = record.geometry
        wkt = geometry.as_text
        data = { :metadata => record.attributes, feature_type: FEATURE_TYPE_FOR_DIMENSION.fetch(geometry.dimension) }

        if proj4 == PROJ4_4326
          data[:geog] = wkt
        else
          data[:geog] = ActiveRecord::Base.connection.select_value <<-SQL
            SELECT ST_Transform(ST_GeomFromText('#{wkt}'), '#{proj4}', 4326) AS geog
          SQL
        end

        return data
      end

      def open_shapefile(file, &block)
        # the individual SHP file for processing (automatically extracted from a ZIP archive if necessary)
        file = possible_shp_files.first if Unzip.is_zip?(file)
        projected_file = project_to_4326(file.path)
        file = projected_file || file
        validate_shapefile!(file.path)
        proj4 = proj4_projection(file.path)

        RGeo::Shapefile::Reader.open(file.path) do |records| # Fall back to unprojected geometry if projection fails
          block.call records, proj4
        end
      ensure
        if projected_file
          projected_file.close
          ::File.delete(projected_file)
        end
      end

      def proj4_projection(file_path)
        proj4_from_file(file_path) || default_proj4_projection || raise(IndeterminateShapefileProjection, 'Could not determine shapefile projection. Check that `gdalsrsinfo` is installed.')
      end

      def validate_shapefile!(file_path)
        Validation.validate_shapefile!(::File.open(file_path), default_proj4_projection: default_proj4_projection)
      end

      # Use OGR2OGR to reproject into EPSG:4326 so we can skip the reprojection step per-feature
      def project_to_4326(file_path)
        output_path = Tempfile.create([::File.basename(file_path, '.shp') + '_epsg_4326_', '.shp']) { |file| file.path }
        return unless (proj4 = proj4_from_file(file_path))
        return unless system("ogr2ogr -s_srs '#{proj4}' -t_srs EPSG:4326 #{output_path} #{file_path}")
        return ::File.open(output_path)
      end

      def proj4_from_file(file_path)
        # Sanitize: "'+proj=utm +zone=11 +datum=NAD83 +units=m +no_defs '\n" and lately
        #           "+proj=utm +zone=11 +datum=NAD83 +units=m +no_defs \n" to
        #           "+proj=utm +zone=11 +datum=NAD83 +units=m +no_defs"
        `gdalsrsinfo "#{file_path}" -o proj4`.strip.remove(/^'|'$/).presence
      end

      # a zip archive may contain multiple SHP files
      def possible_shp_files
        @possible_shp_files ||= begin
          Download.open_each(archive, unzip: /\.shp$/, downcase: true)
        rescue Unzip::PathNotFound
          raise ::SpatialFeatures::Importers::IncompleteShapefileArchive, "Shapefile archive is missing a SHP file"
        end
      end

      def archive
        @archive ||= Download.open(@data)
      end
    end

    # ERRORS
    class IndeterminateShapefileProjection < SpatialFeatures::ImportError; end
    class IncompleteShapefileArchive < SpatialFeatures::ImportError; end
    class InvalidShapefileArchive < SpatialFeatures::ImportError; end
  end
end
