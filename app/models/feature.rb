class Feature < AbstractFeature
  class_attribute :automatically_refresh_aggregate
  self.automatically_refresh_aggregate = true

  class_attribute :lowres_precision
  self.lowres_precision = 5

  has_one :aggregate_feature, lambda { |feature| where(:spatial_model_type => feature.spatial_model_type) }, :foreign_key => :spatial_model_id, :primary_key => :spatial_model_id

  validates_inclusion_of :feature_type, :in => FEATURE_TYPES

  after_save :refresh_aggregate, if: :spatial_model_id

  def refresh_aggregate
    build_aggregate_feature unless aggregate_feature&.persisted?
    aggregate_feature.refresh
  end

  # Features are used for display so we also cache their KML representation
  def self.cache_derivatives(options = {})
    super
    update_all <<-SQL.squish
      kml          = ST_AsKML(geog, 6),
      kml_lowres   = ST_AsKML(geom_lowres, #{options.fetch(:lowres_precision, lowres_precision)}),
      kml_centroid = ST_AsKML(centroid)
    SQL
  end
end
