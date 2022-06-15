module SpatialFeatures
  module Importers
    class Geomark < KMLFile
      def initialize(geomark, **options)
        super geomark_url(geomark), **options
      end

      private

      def geomark_url(geomark)
        "http://apps.gov.bc.ca/pub/geomark/geomarks/#{geomark}/parts.kml?srid=4326"
      end
    end
  end
end
