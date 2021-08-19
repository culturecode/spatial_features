require 'ostruct'
require 'digest/md5'

module SpatialFeatures
  module Importers
    class Shapefile < Base
      class_attribute :default_proj4_projection

      def initialize(data, *args, proj4: nil, **options)
        @proj4 = options.delete(:proj4)
        @shp_file_name = options.delete(:shp_file_name)
        super(data, **options)
      end

      def cache_key
        @cache_key ||= Digest::MD5.file(archive).to_s
      end

      private

      attr_reader :shp_file_name

      def each_record(&block)
        RGeo::Shapefile::Reader.open(file.path) do |records|
          records.each do |record|
            yield OpenStruct.new data_from_wkt(record.geometry.as_text, proj4_projection).merge(:metadata => record.attributes) if record.geometry.present?
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

      def proj4_projection
        @proj4 ||= proj4_from_file || default_proj4_projection || raise(IndeterminateShapefileProjection, 'Could not determine shapefile projection. Check that `gdalsrsinfo` is installed.')
      end

      def proj4_from_file
        # Sanitize: "'+proj=utm +zone=11 +datum=NAD83 +units=m +no_defs '\n" and lately
        #           "+proj=utm +zone=11 +datum=NAD83 +units=m +no_defs \n" to
        #           "+proj=utm +zone=11 +datum=NAD83 +units=m +no_defs"
        `gdalsrsinfo "#{file.path}" -o proj4`.strip.remove(/^'|'$/).presence
      end

      def data_from_wkt(wkt, proj4)
        ActiveRecord::Base.connection.select_one <<-SQL
          SELECT ST_Transform(ST_GeomFromText('#{wkt}'), '#{proj4}', 4326) AS geog, GeometryType(ST_GeomFromText('#{wkt}')) AS feature_type
        SQL
      end

      def file
        @file ||= (requested_shp_file || possible_shp_files.first)
      end

      # a zip archive may contain multiple SHP files
      def possible_shp_files
        @possible_shp_files ||= begin
          validate_file!
          Download.open_each(archive, unzip: /\.shp$/, downcase: true)
        end
      end

      def requested_shp_file
        return unless shp_file_name
        expected_match = "*/#{shp_file_name}"
        file = possible_shp_files.find do |candidate|
          ::File.fnmatch?(expected_match, candidate.path)
        end

        raise SpatialFeatures::Unzip::PathNotFound, "could not find #{shp_file_name} in #{possible_shp_files.map(&:path)}" \
          unless file

        file
      end

      def validate_file!
        return unless Unzip.is_zip?(archive)
        Validation.validate_shapefile_archive!(Download.entries(archive), default_proj4_projection: default_proj4_projection)
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
