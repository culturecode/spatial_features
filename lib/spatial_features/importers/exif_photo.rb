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
          metadata: {}
        )
      end
    end
  end
end
