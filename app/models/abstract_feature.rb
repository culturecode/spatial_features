class AbstractFeature < ActiveRecord::Base
  self.table_name = 'features'

  class_attribute :automatically_cache_derivatives
  self.automatically_cache_derivatives = true

  class_attribute :lowres_simplification
  self.lowres_simplification = 2 # Threshold in meters

  belongs_to :spatial_model, :polymorphic => :true, :autosave => false

  attr_writer :make_valid

  FEATURE_TYPES = %w(polygon point line)

  before_validation :sanitize_feature_type
  validates_presence_of :geog
  validate :validate_geometry, if: :will_save_change_to_geog?
  before_save :sanitize, if: :will_save_change_to_geog?
  after_save :cache_derivatives, :if => [:automatically_cache_derivatives?, :saved_change_to_geog?]

  # for Rails >= 5 ActiveRecord collections we override the collection_cache_key
  # to prevent Rails doing its default query on `updated_at`
  def self.collection_cache_key(_collection, _timestamp_column)
    self.cache_key
  end

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

  def self.within_distance_of_point(lat, lng, distance_in_meters)
    where("ST_DWithin(features.geog, ST_Point(:lng, :lat), :distance)", :lat => lat, :lng => lng, :distance => distance_in_meters)
  end

  def self.area_in_square_meters(geom = 'geom_lowres')
    current_scope = all.polygons
    unscoped { SpatialFeatures::Utils.select_db_value(select("ST_Area(ST_Union(#{geom}))").from(current_scope, :features)).to_f }
  end

  def self.total_intersection_area_in_square_meters(other_features, geom = 'geom_lowres')
    scope = unscope(:select).select("ST_Union(#{geom}) AS geom").polygons
    other_scope = other_features.polygons

    query = base_class.unscoped.select('ST_Area(ST_Intersection(ST_Union(features.geom), ST_Union(other_features.geom)))')
                    .from(scope, "features")
                    .joins("INNER JOIN (#{other_scope.to_sql}) AS other_features ON ST_Intersects(features.geom, other_features.geom)")
    return SpatialFeatures::Utils.select_db_value(query).to_f
  end

  def self.intersecting(other)
    join_other_features(other).where('ST_Intersects(features.geom_lowres, other_features.geom_lowres)').uniq
  end

  def self.within_distance(other, distance_in_meters)
    join_other_features(other).where('ST_DWithin(features.geom_lowres, other_features.geom_lowres, ?)', distance_in_meters).uniq
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

  def self.without_caching_derivatives(&block)
    old = automatically_cache_derivatives
    self.automatically_cache_derivatives = false
    block.call
  ensure
    self.automatically_cache_derivatives = old
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
      geom_lowres  = ST_SimplifyPreserveTopology(geom, #{options.fetch(:lowres_simplification, lowres_simplification)}),
      tilegeom     = ST_Transform(geom, 3857)
    SQL

    invalid('geom_lowres').update_all <<-SQL.squish
      geom_lowres  = ST_Buffer(geom_lowres, 0)
    SQL
  end

  def self.mvt(tile_x, tile_y, zoom, properties: true, centroids: false, metadata: {}, scope: nil)
    if centroids
      column = 'ST_Transform(centroid::geometry, 3857)' # MVT works in SRID 3857
    else
      column = 'tilegeom'
    end

    subquery = all
    subquery = subquery
                .select("ST_AsMVTGeom(#{column}, ST_TileEnvelope(#{zoom}, #{tile_x}, #{tile_y}), extent => 4096, buffer => 64) AS geom")
                .select('id')
                .where("#{column} && ST_TileEnvelope(#{zoom}, #{tile_x}, #{tile_y}, margin => (64.0 / 4096))")
                .order(:id)

    # Merge additional scopes in to allow joins and other columns to be included in the feature output
    subquery = subquery.merge(scope) unless scope.nil?

    # Add metadata
    metadata.each do |column, value|
      subquery = subquery.select("#{value} AS #{column}")
    end

    select_sql = <<~SQL
      SELECT ST_AsMVT(mvtgeom.*, 'default', 4096, 'geom', 'id')
      FROM (#{subquery.to_sql}) mvtgeom;
    SQL

    # Result is a hex string representing the desired binary output so we need to convert it to binary
    result = SpatialFeatures::Utils.select_db_value(select_sql)
    result.remove!(/^\\x/)
    result = result.scan(/../).map(&:hex).pack('c*')

    return result
  end

  def self.geojson(lowres: false, precision: 6, properties: true, srid: 4326, centroids: false, features_only: false, include_record_identifiers: false) # default srid is 4326 so output is Google Maps compatible
    if centroids
      column = 'centroid'
    elsif lowres
      column = "ST_Transform(geom_lowres, #{srid})"
    else
      column = 'geog'
    end

    properties_sql = []

    if include_record_identifiers
      properties_sql << "hstore(ARRAY['feature_name', name::varchar, 'feature_id', id::varchar, 'spatial_model_type', spatial_model_type::varchar, 'spatial_model_id', spatial_model_id::varchar])"
    end

    if properties
      properties_sql << "metadata"
      properties_sql << <<~SQL
        hstore(ARRAY['feature_area', area::varchar])
      SQL
    end

    if properties.is_a?(Hash)
      properties_sql << <<~SQL
        hstore(ARRAY[#{properties.flatten.map {|e| "'#{e.to_s}'" }.join(',')}])
      SQL
    end

    properties_sql = <<~SQL if properties_sql.present?
      , 'properties', hstore_to_json(#{properties_sql.join(' || ')})
    SQL

    sql = <<~SQL
      json_agg(
        json_build_object(
          'type', 'Feature',
          'geometry', ST_AsGeoJSON(#{column}, #{precision})::json
          #{properties_sql}
        )
      )
    SQL

    sql = <<~SQL unless features_only
      json_build_object(
        'type', 'FeatureCollection',
        'features', #{sql}
      )
    SQL
    SpatialFeatures::Utils.select_db_value(all.select(sql))
  end

  def self.bounds
    values = pluck('MAX(north) AS north, MAX(east) AS east, MIN(south) AS south, MIN(west) AS west').first
    [:north, :east, :south, :west].zip(values).to_h.with_indifferent_access.transform_values!(&:to_f) if values&.compact.present?
  end

  def bounds
    slice(:north, :east, :south, :west).with_indifferent_access.transform_values!(&:to_f)
  end

  def cache_derivatives(*args)
    self.class.default_scoped.where(:id => self.id).cache_derivatives(*args)
  end

  def kml(options = {})
    column = options[:lowres] ? 'geom_lowres' : 'geog'
    return SpatialFeatures::Utils.select_db_value(self.class.where(:id => id).select("ST_AsKML(#{column}, 6)"))
  end

  def geojson(*args)
    self.class.where(id: id).geojson(*args)
  end

  def make_valid?
    @make_valid
  end

  private

  def make_valid
    self.geog = SpatialFeatures::Utils.select_db_value("SELECT ST_Buffer('#{sanitize}', 0)")
  end

  # Use ST_Force2D to discard z-coordinates that cause failures later in the process
  def sanitize
    self.geog = SpatialFeatures::Utils.select_db_value("SELECT ST_Force2D('#{geog}')")
  end

  SRID_CACHE = {}
  def self.detect_srid(column_name)
    SRID_CACHE[column_name] ||= SpatialFeatures::Utils.select_db_value("SELECT Find_SRID('public', '#{table_name}', '#{column_name}')")
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
    error = klass.connection.select_one(klass.unscoped.invalid.from("(SELECT '#{sanitize_input_for_sql(self.geog)}'::geography::geometry AS geog) #{klass.table_name}")) # Ensure we cast to geography because the geog attribute value may not have been coerced to geography yet, so we want it to apply the +-180/90 bounds to any odd geometry that will happen when we save to the database
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
