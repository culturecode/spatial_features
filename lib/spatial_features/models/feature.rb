class Feature < ActiveRecord::Base
  belongs_to :spatial_model, :polymorphic => :true

  before_validation :sanitize_feature_type
  validates_presence_of :geog
  validate :geometry_is_valid
  validates_inclusion_of :feature_type, :in => ['polygon', 'point', 'line']
  after_save :cache_derivatives

  store :metadata

  def self.polygons
    where(:feature_type => 'polygon')
  end

  def self.lines
    where(:feature_type => 'line')
  end

  def self.points
    where(:feature_type => 'point')
  end

  def self.for_kml(options = {})
    if options[:simplified]
      select("features.name, features.kml, features.metadata").where("features.name IS NULL OR features.name NOT IN ('s', 't')")
    else
      select("features.name, ST_AsKML(features.geog, 6) AS kml, features.metadata")
    end
  end

  def self.invalid
    select('features.*, ST_IsValidReason(geog::geometry) AS invalid_geometry_message').where.not('ST_IsValid(geog::geometry)')
  end

  def envelope(buffer_in_meters = 0)
    envelope_json = JSON.parse(self.class.select("ST_AsGeoJSON(ST_Envelope(ST_Buffer(features.geog, #{buffer_in_meters})::geometry)) AS result").where(:id => id).first.result)
    envelope_json["coordinates"].first.values_at(0,2)
  end

  private

  def cache_derivatives
    self.class.connection.execute "UPDATE features SET geog_lowres = ST_SimplifyPreserveTopology(geog::geometry, 0.0001) WHERE id = #{self.id}"
    self.class.connection.execute "UPDATE features SET kml = ST_AsKML(geog_lowres::geometry, 5) WHERE id = #{self.id}"
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
