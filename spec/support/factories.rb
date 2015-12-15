def create_record_with_polygon(klass, *coordinates)
  record = klass.create!
  coordinates.each do |coords|
    record.features << build_polygon(coords)
  end
  record
end

def build_polygon(coordinates)
  # Avoid crossing the equator for test values in order to avoid projection error
  raise 'For test purposes, coordinates cannot be negative' if coordinates.include?('-')

  geom_projection_offset_lng = 1
  geom_projection_offset_lat = 1
  coordinates = coordinates.split(/\s*,\s*/).collect do |pair|
    lng, lat = pair.split
    lng = lng.to_f + geom_projection_offset_lng
    lat = lat.to_f + geom_projection_offset_lat
    "#{lng} #{lat}"
  end.join(',')

  geog = Feature.connection.select_value("
    SELECT ST_Transform(ST_GeometryFromText( 'POLYGON((#{coordinates}))', 26910 ), 4326)
  ")

  Feature.polygons.new(:geog => geog)
end
