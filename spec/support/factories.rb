def create_record_with_polygon(klass, *coordinates)
  record = klass.create!
  coordinates.each do |coords|
    record.features << build_polygon(coords)
  end

  record.update! :features_hash => 'some new value'

  SpatialFeatures.cache_proximity(*Feature.pluck(:spatial_model_type).uniq.collect(&:constantize)) # automatically update spatial cache

  record
end

class Rectangle
  def initialize(width, height, options = {})
    y_min = options[:y].to_f
    x_min = options[:x].to_f
    y_max = height + y_min
    x_max = width + x_min
    @coordinates = "#{x_min} #{y_min}, #{x_min} #{y_max}, #{x_max} #{y_max}, #{x_max} #{y_min}, #{x_min} #{y_min}"
  end

  def to_s
    @coordinates
  end
end

def create_polygon(*args)
  polygon = build_polygon(*args)
  polygon.save!
  polygon.reload
  return polygon
end

def build_polygon(coordinates, attributes = {})
  coordinates = coordinates.to_s

  # Avoid crossing the equator for test values in order to avoid projection error
  raise 'For test purposes, coordinates cannot be negative' if coordinates.include?('-')

  # Offset to be within NAD83 boundary
  geom_projection_offset_easting = 497042
  geom_projection_offset_northing = 6155650

  coordinates = coordinates.split(/\s*,\s*/).collect do |pair|
    easting, northing = pair.split
    easting = easting.to_f + geom_projection_offset_easting
    northing = northing.to_f + geom_projection_offset_northing
    "#{easting} #{northing}"
  end.join(',')

  geog = SpatialFeatures::Utils.select_db_value("
    SELECT ST_Transform(ST_GeometryFromText( 'POLYGON((#{coordinates}))', 26910 ), 4326)
  ")

  Feature.polygons.new(attributes.merge :geog => geog)
end

def create_record_with_point(klass, *coordinates)
  record = klass.create!
  coordinates.each do |coords|
    record.features << build_point(coords)
  end

  record.update! :features_hash => 'some new value'

  SpatialFeatures.cache_proximity(*Feature.pluck(:spatial_model_type).uniq.collect(&:constantize)) # automatically update spatial cache

  record
end

class Point
  def initialize(x, y)
    @coordinates = "#{x} #{y}"
  end

  def to_s
    @coordinates
  end
end

def create_point(x, y)
  point = build_point("#{x} #{y}")
  point.save!
  return point
end

def build_point(coordinates, attributes = {})
  coordinates = coordinates.to_s

  # Avoid crossing the equator for test values in order to avoid projection error
  raise 'For test purposes, coordinates cannot be negative' if coordinates.include?('-')

  # Offset to be within NAD83 boundary
  geom_projection_offset_easting = 497042
  geom_projection_offset_northing = 6155650

  easting, northing = coordinates.split
  easting = easting.to_f + geom_projection_offset_easting
  northing = northing.to_f + geom_projection_offset_northing
  coordinates = "#{easting} #{northing}"

  geog = SpatialFeatures::Utils.select_db_value("
    SELECT ST_Transform(ST_GeometryFromText( 'POINT(#{coordinates})', 26910 ), 4326)
  ")

  Feature.points.new(attributes.merge :geog => geog)
end
