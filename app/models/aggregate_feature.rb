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
    compacted_feature_array_sql = <<~SQL
      array_remove(
        array_remove(
          array_remove(#{feature_array_sql},
          ST_GeomFromText('Point EMPTY')),
        ST_GeomFromText('Linestring EMPTY')),
      ST_GeomFromText('Polygon EMPTY'))
    SQL

    self.geog = ActiveRecord::Base.connection.select_value <<~SQL
      SELECT ST_Collect(#{compacted_feature_array_sql})::geography
    SQL
    self.save!
  end
end
