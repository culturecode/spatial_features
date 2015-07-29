class SpatialCache < ActiveRecord::Base
  belongs_to :spatial_model, :polymorphic => true, :inverse_of => :spatial_cache

  def stale?
    spatial_model.has_spatial_features_hash? && self.features_hash != spatial_model.features_hash
  end
end
