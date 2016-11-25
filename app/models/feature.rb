class Feature < ActiveRecord::Base
  belongs_to :spatial_model, :polymorphic => :true

  attr_writer :make_valid

  before_validation :sanitize_feature_type
  validates_presence_of :geog
  validate :geometry_is_valid
  validates_inclusion_of :feature_type, :in => ['polygon', 'point', 'line']
  before_save :sanitize
  before_save :make_valid, if: :make_valid?
  after_save :cache_derivatives

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
    unscoped
      .from("(#{select("ST_Union(geom) AS geom").to_sql}) features, (#{other_features.to_sql}) other_features")
      .pluck('ST_Area(ST_UNION(ST_Intersection(features.geom, other_features.geom)))')
      .first.to_f
  end

  def self.intersecting(other)
    join_other_features(other).where('ST_Intersects(features.geom_lowres, other_features.geom_lowres)').uniq
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

  def make_valid?
    @make_valid
  end

  private

  def make_valid
    self.geog = ActiveRecord::Base.connection.select_value("SELECT ST_CollectionExtract(ST_MakeValid('#{sanitize}'),3)")
  end

  # Use ST_Force_2D to discard z-coordinates that cause failures later in the process
  def sanitize
    self.geog = ActiveRecord::Base.connection.select_value("SELECT ST_Force2D('#{geog}')")
  end

  def self.detect_srid(column_name)
    connection.select_value("SELECT Find_SRID('public', '#{table_name}', '#{column_name}')")
  end

  def self.join_other_features(other)
    joins('INNER JOIN features AS other_features ON true').where(:other_features => {:id => other})
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
