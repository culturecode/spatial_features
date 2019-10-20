class Feature < AbstractFeature
  class_attribute :automatically_refresh_aggregate
  self.automatically_refresh_aggregate = true

  class_attribute :lowres_precision
  self.lowres_precision = 5

  has_one :aggregate_feature, lambda { |feature| where(:spatial_model_type => feature.spatial_model_type) }, :foreign_key => :spatial_model_id, :primary_key => :spatial_model_id

  validates_inclusion_of :feature_type, :in => FEATURE_TYPES

  after_save :refresh_aggregate, if: :automatically_refresh_aggregate?

  def self.defer_aggregate_refresh(&block)
    start_at = Feature.maximum(:id).to_i + 1
    output = without_aggregate_refresh(&block)

    where(:id => start_at..Float::INFINITY).refresh_aggregates

    return output
  end

  def self.without_aggregate_refresh
    old = Feature.automatically_refresh_aggregate
    Feature.automatically_refresh_aggregate = false
    yield
  ensure
    Feature.automatically_refresh_aggregate = old
  end

  def self.refresh_aggregates
    # Find one feature from each spatial model and trigger the aggregate feature refresh
    ids = select('MAX(id)')
            .where.not(:spatial_model_type => nil, :spatial_model_id => nil)
            .group('spatial_model_type, spatial_model_id')

    where(:id => ids).find_each(&:refresh_aggregate)
  end

  def refresh_aggregate
    build_aggregate_feature unless aggregate_feature&.persisted?
    aggregate_feature.refresh
  end

  def automatically_refresh_aggregate?
    # Check if there is a spatial model id because nothing prevents is from creating a Feature without one. Depending on
    # how you assign a feature to a record, you may end up saving it before assigning it to a record, thereby leaving
    # this field blank.
    spatial_model_id? && automatically_refresh_aggregate
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
