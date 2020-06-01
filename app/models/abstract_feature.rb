class AbstractFeature < ActiveRecord::Base
  self.table_name = 'features'

  class_attribute :lowres_simplification
  self.lowres_simplification = 2 # Threshold in meters

  belongs_to :spatial_model, :polymorphic => :true, :autosave => false

  attr_writer :make_valid

  FEATURE_TYPES = %w(polygon point line)

  before_validation :sanitize_feature_type
  validates_presence_of :geog
  validate :validate_geometry
  before_save :sanitize
  after_save :cache_derivatives, :if => :saved_change_to_geog?

  def self.cache_key
    "#{maximum(:id)}-#{count}"
  end

  def self.with_metadata(k, v)
    if k.present? && v.present?
      where('metadata->? = ?', k, v)
    else
      all
    end
  end

  def self.polygons
    where(:feature_type => 'polygon')
  end

  def self.lines
    where(:feature_type => 'line')
  end

  def self.points
    where(:feature_type => 'point')
  end

  def self.within_distance(lat, lng, distance_in_meters)
    # where("ST_DWithin(features.geog, ST_SetSRID( ST_Point( -71.104, 42.315), 4326)::geography, :distance)", :lat => lat, :lng => lng, :distance => distance_in_meters)
    where("ST_DWithin(features.geog, ST_Point(:lng, :lat), :distance)", :lat => lat, :lng => lng, :distance => distance_in_meters)
  end

  def self.area_in_square_meters(geom = 'geom_lowres')
    current_scope = all.polygons
    unscoped { connection.select_value(select("ST_Area(ST_Union(#{geom}))").from(current_scope, :features)).to_f }
  end

  def self.total_intersection_area_in_square_meters(other_features, geom = 'geom_lowres')
    scope = unscope(:select).select("ST_Union(#{geom}) AS geom").polygons
    other_scope = other_features.polygons

    query = base_class.unscoped.select('ST_Area(ST_Intersection(ST_Union(features.geom), ST_Union(other_features.geom)))')
                    .from(scope, "features")
                    .joins("INNER JOIN (#{other_scope.to_sql}) AS other_features ON ST_Intersects(features.geom, other_features.geom)")
    return connection.select_value(query).to_f
  end

  def self.intersecting(other)
    join_other_features(other).where('ST_Intersects(features.geom_lowres, other_features.geom_lowres)').uniq
  end

  def self.invalid(column = 'geog::geometry')
    select("features.*, ST_IsValidReason(#{column}) AS invalid_geometry_message").where.not("ST_IsValid(#{column})")
  end

  def self.valid
    where('ST_IsValid(geog::geometry)')
  end

  def envelope(buffer_in_meters = 0)
    envelope_json = JSON.parse(self.class.select("ST_AsGeoJSON(ST_Envelope(ST_Buffer(features.geog, #{buffer_in_meters})::geometry)) AS result").where(:id => id).first.result)
    envelope_json = envelope_json["coordinates"].first

    raise "Can't calculate envelope for Feature #{self.id}" if envelope_json.blank?

    return envelope_json.values_at(0,2)
  end

  def self.cache_derivatives(options = {})
    update_all <<-SQL.squish
      geom         = ST_Transform(geog::geometry, #{detect_srid('geom')}),
      north        = ST_YMax(geog::geometry),
      east         = ST_XMax(geog::geometry),
      south        = ST_YMin(geog::geometry),
      west         = ST_XMin(geog::geometry),
      area         = ST_Area(geog),
      centroid     = ST_PointOnSurface(geog::geometry)
    SQL

    invalid('geom').update_all <<-SQL.squish
      geom         = ST_Buffer(geom, 0)
    SQL

    update_all <<-SQL.squish
      geom_lowres  = ST_SimplifyPreserveTopology(geom, #{options.fetch(:lowres_simplification, lowres_simplification)})
    SQL

    invalid('geom_lowres').update_all <<-SQL.squish
      geom_lowres  = ST_Buffer(geom_lowres, 0)
    SQL
  end

  def self.geojson(lowres: false, precision: 6, properties: {}, srid: 4326) # default srid is 4326 so output is Google Maps compatible
    column = lowres ? "ST_Transform(geom_lowres, #{srid})" : 'geog'
    properties_sql = <<~SQL if properties.present?
      , 'properties', json_build_object(#{properties.map {|k,v| "'#{k}',#{v}" }.join(',') })
    SQL

    sql = <<~SQL
      json_build_object(
        'type', 'FeatureCollection',
        'features', json_agg(
          json_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(#{column}, #{precision})::json
            #{properties_sql}
          )
        )
      )
    SQL
    connection.select_value(all.select(sql))
  end

  def feature_bounds
    {n: north, e: east, s: south, w: west}
  end

  def cache_derivatives(*args)
    self.class.where(:id => self.id).cache_derivatives(*args)
  end

  def kml(options = {})
    geometry = options[:lowres] ? kml_lowres : super()
    geometry = "<MultiGeometry>#{geometry}#{kml_centroid}</MultiGeometry>" if options[:centroid]
    return geometry
  end

  def geojson(*args)
    self.class.where(id: id).geojson(*args)
  end

  def make_valid?
    @make_valid
  end

  private

  def make_valid
    self.geog = ActiveRecord::Base.connection.select_value("SELECT ST_Buffer('#{sanitize}', 0)")
  end

  # Use ST_Force2D to discard z-coordinates that cause failures later in the process
  def sanitize
    self.geog = ActiveRecord::Base.connection.select_value("SELECT ST_Force2D('#{geog}')")
  end

  SRID_CACHE = {}
  def self.detect_srid(column_name)
    SRID_CACHE[column_name] ||= connection.select_value("SELECT Find_SRID('public', '#{table_name}', '#{column_name}')")
  end

  def self.join_other_features(other)
    joins('INNER JOIN features AS other_features ON true').where(:other_features => {:id => other})
  end

  def validate_geometry
    return unless geog?

    error = geometry_validation_message
    if error && make_valid?
      make_valid
      self.make_valid = false
      validate_geometry
    elsif error
      errors.add :geog, error
    end
  end

  def geometry_validation_message
    klass = self.class.base_class # Use the base class because we don't want to have to include a type column in our select
    error = klass.connection.select_one(klass.unscoped.invalid.from("(SELECT '#{sanitize_input_for_sql(self.geog)}'::geometry AS geog) #{klass.table_name}"))
    return error.fetch('invalid_geometry_message') if error
  end

  def sanitize_feature_type
    self.feature_type = FEATURE_TYPES.find {|type| self.feature_type.to_s.strip.downcase.include?(type) }
  end

  def sanitize_input_for_sql(input)
    self.class.send(:sanitize_sql_for_conditions, input)
  end

  def saved_change_to_geog?
    if Rails.version >= '5.1'
      super
    else
      geog_changed?
    end
  end
end
