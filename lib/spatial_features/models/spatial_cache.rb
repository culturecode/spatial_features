class SpatialCache < ActiveRecord::Base
  belongs_to :spatial_model, :polymorphic => true
end
