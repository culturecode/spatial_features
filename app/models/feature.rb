class Feature < ActiveRecord::Base
  belongs_to :spatial_model, :polymorphic => :true

  before_validation :sanitize_feature_type
  validates_presence_of :geog
  validate :geometry_is_valid
  validates_inclusion_of :feature_type, :in => ['polygon', 'point', 'line']
  after_save :cache_derivatives

  GEOM_COLUMN = "geom_lowres"
  FEATURES_ALIAS = 'features'
  OTHER_FEATURES_ALIAS = 'other_features'
  FEATURES_AND_OTHER_FEATURES = "#{FEATURES_ALIAS}.#{GEOM_COLUMN}, #{OTHER_FEATURES_ALIAS}.#{GEOM_COLUMN}"


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

  def self.area_in_square_meters
    current_scope = all
    unscoped { connection.select_value(select('ST_Area(ST_Union(geom))').from(current_scope, :features)).to_f }
  end

  def self.total_intersection_area_in_square_meters(other_features)
      select("ST_Union(#{FEATURES_ALIAS}.#{GEOM_COLUMN}) AS #{GEOM_COLUMN}")
      .join_features(other_features)
      .pluck("ST_Area(ST_UNION(ST_Intersection(#{FEATURES_AND_OTHER_FEATURES})))")
      .first.to_f
  end

  def self.within_buffer(other, buffer_in_meters, options = {})
    distance, intersection_area = options[:distance], options[:intersection_area]

    if buffer_in_meters.to_f == 0
      intersecting(other, options)
    elsif distance || intersection_area
      join_features(intersecting(other, :intersection_area => true, :group => options[:group]), 'LEFT OUTER', 'USING (id)', 'other_features')
        .join_features(not_intersecting(other, :distance => true, :group => options[:group]), 'LEFT OUTER', 'USING (id)', 'disjoint_features')
    else
      join_features(other).where("ST_DWithin(#{FEATURES_AND_OTHER_FEATURES}, ?)", buffer_in_meters).with_option_scopes(options)
    end
  end

  def self.intersecting(other, options = {})
    join_features(other, options[:join]).where("ST_Intersects(#{FEATURES_AND_OTHER_FEATURES})").with_option_scopes(options)
  end

  def self.not_intersecting(other, options = {})
    join_features(other, options[:join]).where.not("ST_Intersects(#{FEATURES_AND_OTHER_FEATURES})").with_option_scopes(options)
  end

  def self.covering(other)
    join_features(other).where("ST_Covers(#{FEATURES_AND_OTHER_FEATURES})")
  end

  def self.invalid
    select('features.*, ST_IsValidReason(geog::geometry) AS invalid_geometry_message').where.not('ST_IsValid(geog::geometry)')
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
    options.reverse_merge! :lowres_simplification => 2, :lowres_precision => 5

    update_all <<-SQL.squish
      geom         = ST_Transform(geog::geometry, #{detect_srid('geom')}),
      north        = ST_YMax(geog::geometry),
      east         = ST_XMax(geog::geometry),
      south        = ST_YMin(geog::geometry),
      west         = ST_XMin(geog::geometry),
      area         = ST_Area(geog),
      centroid     = ST_PointOnSurface(geog::geometry)
    SQL

    update_all <<-SQL.squish
      geom_lowres  = ST_SimplifyPreserveTopology(geom, #{options[:lowres_simplification]})
    SQL

    update_all <<-SQL.squish
      kml          = ST_AsKML(geog, 6),
      kml_lowres   = ST_AsKML(geom_lowres, #{options[:lowres_precision]}),
      kml_centroid = ST_AsKML(centroid)
    SQL
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

  protected

  def self.with_option_scopes(options)
    scope = all

    if options[:group]
      scope = scope.unscope(:select)
      scope = scope.with_grouped_distance if options[:distance]
      scope = scope.with_grouped_intersection_area if options[:intersection_area]
    else
      scope = scope.with_distance if options[:distance]
      scope = scope.with_intersection_area if options[:intersection_area]
    end

    return scope
  end

  def self.with_distance
    select_table.select("ST_Distance(#{FEATURES_AND_OTHER_FEATURES}) AS distance_in_meters")
  end

  def self.with_intersection_area
    select_table.select("ST_Area(ST_Intersection(#{FEATURES_AND_OTHER_FEATURES})) AS intersection_area_in_square_meters")
  end

  def self.with_grouped_distance
    in_feature_groups.select("MIN(ST_Distance(#{FEATURES_AND_OTHER_FEATURES})) AS distance_in_meters")
  end

  def self.with_grouped_intersection_area
    in_feature_groups.select("ST_Area(ST_Union(ST_Intersection(#{FEATURES_AND_OTHER_FEATURES}))) AS intersection_area_in_square_meters")
  end

  def self.in_feature_groups
    columns = "#{FEATURES_ALIAS}.spatial_model_id, #{FEATURES_ALIAS}.spatial_model_type"
    group(columns).select(columns)
  end

  def self.join_features(other_features, join_type = "INNER", condition = "ON true", other_alias = OTHER_FEATURES_ALIAS)
    other_features = other_features.is_a?(ActiveRecord::Base) ? unscoped { where(:id => other_features) } : unscoped { other_features.all }
    joins("#{join_type} JOIN (#{other_features.to_sql}) #{other_alias} #{condition}")
  end

  def self.select_table(table_name = FEATURES_ALIAS)
    unscope(:select) == all ? select("#{table_name}.*") : self
  end

  private

  def self.detect_srid(column_name)
    connection.select_value("SELECT Find_SRID('public', '#{table_name}', '#{column_name}')")
  end

  def geometry_is_valid
    if geog?
      instance = self.class.unscoped.invalid.from("(SELECT '#{sanitize_input_for_sql(self.geog)}'::geometry AS geog) #{self.class.table_name}").to_a.first
      errors.add :geog, instance.invalid_geometry_message if instance
    end
  end

  def sanitize_feature_type
    self.feature_type = self.feature_type.to_s.strip.downcase
  end

  def sanitize_input_for_sql(input)
    self.class.send(:sanitize_sql_for_conditions, input)
  end
end
