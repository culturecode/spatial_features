class SpatialCache < ActiveRecord::Base
  belongs_to :spatial_model, :polymorphic => true, :inverse_of => :spatial_caches

  def self.between(spatial_model, klass)
    where(SpatialFeatures::Utils.polymorphic_condition(spatial_model, 'spatial_model'))
    .where(:intersection_model_type => SpatialFeatures::Utils.class_name_with_ancestors(klass))
  end

  def stale?
    spatial_model.has_spatial_features_hash? && self.features_hash != spatial_model.features_hash
  end
end
