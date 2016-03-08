class Feature < ActiveRecord::Base
  belongs_to :spatial_model, :polymorphic => :true

  before_validation :sanitize_feature_type
  validates_presence_of :geog
  validate :geometry_is_valid
  validates_inclusion_of :feature_type, :in => ['polygon', 'point', 'line']
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

  def self.total_intersection_area_in_square_meters(other)
    scope = join_other_features(other)
      .where('ST_Intersects(features.geog_lowres, other_features.geog_lowres)')
      .select('ST_Area(ST_Intersection(ST_Union(features.geog_lowres::geometry), ST_Union(other_features.geog_lowres::geometry))::geography) AS intersection_area_in_square_meters')

    connection.select_value(scope).to_f
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
    options.reverse_merge! :lowres_simplification => 0.00001, :lowres_precision => 5

    update_all("area        = ST_Area(geog),
                geom        = ST_Transform(geog::geometry, 26910),
                geog_lowres = ST_SimplifyPreserveTopology(geog::geometry, #{options[:lowres_simplification]})"
                .squish)
    update_all("kml         = ST_AsKML(features.geog, 6),
                kml_lowres  = ST_AsKML(geog_lowres::geometry, #{options[:lowres_precision]})"
                .squish)
  end

  def cache_derivatives(*args)
    self.class.where(:id => self.id).cache_derivatives(*args)
  end

  def kml(options = {})
    options[:lowres] ? kml_lowres : super()
  end

  private

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
