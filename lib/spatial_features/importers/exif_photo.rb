require 'exifr/jpeg'
require 'ostruct'
require 'fileutils'

module SpatialFeatures
  module Importers
    class ExifPhoto < Base
      JPEG_PATTERN = /\.jpe?g\z/i.freeze
      NO_PHOTOS = "This archive doesn't contain any JPEG photos.".freeze
      UNREADABLE_PHOTO = "This photo couldn't be read. It may be damaged, or saved in a JPEG format we don't support.".freeze

      def self.create_all(data, **options)
        tmpdir = options.fetch(:tmpdir)
        photos_dir = ::File.join(tmpdir, 'exif_photos')
        FileUtils.mkdir_p(photos_dir)

        files = Download.open_each(data, unzip: JPEG_PATTERN, tmpdir: tmpdir)
        files.map.with_index do |file, index|
          filename = ::File.basename(file.path)

          # Separate directories prevent two photos with the same filename colliding,
          # while keeping the original filename for feature names and warnings.
          staged_path = ::File.join(photos_dir, index.to_s, filename)
          FileUtils.mkdir_p(::File.dirname(staged_path))

          begin
            file.rewind
            ::File.open(staged_path, 'wb') do |staged_file|
              IO.copy_stream(file, staged_file)
            end
          ensure
            file.close
          end

          new(staged_path, **options)
        end
      rescue Unzip::PathNotFound
        raise ImportError, NO_PHOTOS
      ensure
        Array(files).each {|file| file.close unless file.closed? }
      end

      def initialize(data, **options)
        options[:source_identifier] ||= ::File.basename(data.to_s)
        super(data, **options)
      end

      def cache_key
        @cache_key ||= Digest::MD5.file(@data).hexdigest
      end

      private

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
