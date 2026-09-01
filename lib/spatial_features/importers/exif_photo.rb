require 'exifr/jpeg'
require 'ostruct'

module SpatialFeatures
  module Importers
    class ExifPhoto < Base
      private

      def each_record
        photo = EXIFR::JPEG.new(@data)
        gps = photo.gps

        yield OpenStruct.new(
          name: ::File.basename(@data),
          geog: "POINT(#{gps.longitude} #{gps.latitude})",
          metadata: {
            'capture_time' => photo.date_time_original.strftime('%Y-%m-%d %H:%M:%S'),
            'altitude' => gps.altitude.to_s,
            'camera_model' => photo.model
          },
          importable_image_paths: [@data]
        )
      end
    end
  end
end
