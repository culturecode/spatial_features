require 'exifr/jpeg'
require 'ostruct'
require 'fileutils'
require 'tmpdir'

module SpatialFeatures
  module Importers
    class ExifPhoto < Base
      JPEG_PATTERN = /\.jpe?g\z/i.freeze
      NO_PHOTOS = "This archive doesn't contain any JPEG photos.".freeze
      UNREADABLE_PHOTO = "This photo couldn't be read. It may be damaged, or saved in a JPEG format we don't support.".freeze

      def self.create_all(data, **options)
        importers = []
        source_directory = Dir.mktmpdir('spatial_features_exif') unless options[:tmpdir]
        tmpdir = options[:tmpdir] || source_directory
        FileUtils.mkdir_p(tmpdir)
        if data.is_a?(String) && data.match?(Download::REMOTE_URL)
          download = Download.open(data)
          filename = remote_photo_filename(data) unless Unzip.is_zip?(download)
          data = download.path
        end
        files = begin
          Download.open_each(data, unzip: JPEG_PATTERN, tmpdir: tmpdir)
        rescue Unzip::PathNotFound
          raise ImportError, NO_PHOTOS
        end
        files.each do |file|
          importers << stage_photo(file, **options, filename: filename)
        end
        complete = true

        block_given? ? yield(importers) : importers
      ensure
        Array(files).each {|file| file.close unless file.closed? }
        if download && !download.closed?
          download.respond_to?(:close!) ? download.close! : download.close
        end
        importers&.each(&:close) if block_given? || !complete
        FileUtils.remove_entry(source_directory) if source_directory && Dir.exist?(source_directory)
      end

      def initialize(data, owned_directory: nil, **options)
        @owned_directory = owned_directory
        options[:source_identifier] ||= ::File.basename(data.to_s)
        super(data, **options)
      end

      # Call after every consumer has finished with importable_image_paths. Supplied
      # tmpdir directories belong to the caller and are never removed here.
      def close
        FileUtils.remove_entry(@owned_directory) if @owned_directory && Dir.exist?(@owned_directory)
        @owned_directory = nil
      end

      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(
          [Digest::MD5.file(@data).hexdigest, ::File.basename(@data), source_identifier].to_json
        )
      end

      private

      def self.remote_photo_filename(url)
        path = URI::DEFAULT_PARSER.unescape(URI.parse(url).path.to_s).tr('\\', '/')
        filename = ::File.basename(path)
        return if filename.empty? || %w[/ . ..].include?(filename) || filename.include?("\0")

        filename
      end
      private_class_method :remote_photo_filename

      def self.stage_photo(file, filename: nil, **options)
        owned_directory = Dir.mktmpdir('spatial_features_photo') unless options[:tmpdir]
        directory = owned_directory || Dir.mktmpdir('spatial_features_photo', options[:tmpdir])
        staged_path = ::File.join(directory, filename || ::File.basename(file.path))

        file.rewind
        ::File.open(staged_path, 'wb') {|staged_file| IO.copy_stream(file, staged_file) }
        importer = new(staged_path, **options, owned_directory: owned_directory)
      ensure
        file.close
        if !importer && owned_directory && Dir.exist?(owned_directory)
          FileUtils.remove_entry(owned_directory)
        end
      end
      private_class_method :stage_photo

      def each_record
        photo = EXIFR::JPEG.new(@data)
        gps = photo.gps
        unless usable_gps?(gps)
          @warnings << 'No usable GPS coordinates were found in this photo.'
          return
        end

        yield OpenStruct.new(
          name: ::File.basename(@data),
          geog: "POINT(#{gps.longitude} #{gps.latitude})",
          metadata: metadata_from(photo, gps),
          importable_image_paths: [@data]
        )
      rescue EXIFR::MalformedImage
        raise ImportError, UNREADABLE_PHOTO
      end

      def usable_gps?(gps)
        gps && gps.latitude.is_a?(Numeric) && gps.longitude.is_a?(Numeric) &&
          (-90..90).cover?(gps.latitude) && (-180..180).cover?(gps.longitude)
      end

      def metadata_from(photo, gps)
        {
          'capture_time' => photo.date_time_original&.strftime('%Y-%m-%d %H:%M:%S'),
          'altitude' => gps.altitude&.to_s,
          'camera_model' => photo.model.presence
        }.compact
      end
    end
  end
end
