require_dependency SpatialFeatures::Engine.root.join('app/models/abstract_feature')

class AggregateFeature < AbstractFeature
  has_many :features, lambda { |aggregate| where(:spatial_model_type => aggregate.spatial_model_type) }, :foreign_key => :spatial_model_id, :primary_key => :spatial_model_id

  # Aggregate the features for the spatial model into a single feature
  def refresh
    feature_array_sql = <<~SQL
      ARRAY[
        (#{features.select('ST_UNION(ST_CollectionExtract(geog::geometry, 1))').to_sql}),
        (#{features.select('ST_UNION(ST_CollectionExtract(geog::geometry, 2))').to_sql}),
        (#{features.select('ST_UNION(ST_CollectionExtract(geog::geometry, 3))').to_sql})
      ]
    SQL

    # Remove empty features so ST_COLLECT doesn't choke. This seems to be a difference between PostGIS 2.x and 3.x
    self.geog = SpatialFeatures::Utils.select_db_value <<~SQL
      SELECT COALESCE(ST_Collect(unnest)::geography, ST_GeogFromText('MULTIPOLYGON EMPTY'))
      FROM (SELECT unnest(#{feature_array_sql})) AS features
      WHERE NOT ST_IsEmpty(unnest)
    SQL
    self.save!
  end
end
