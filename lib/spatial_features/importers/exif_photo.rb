require 'exifr/jpeg'
require 'ostruct'

module SpatialFeatures
  module Importers
    class ExifPhoto < Base
      def initialize(data, **options)
        options[:source_identifier] ||= ::File.basename(data.to_s)
        super(data, **options)
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
