class SpatialProximity < ActiveRecord::Base
  belongs_to :model_a, :polymorphic => true
  belongs_to :model_b, :polymorphic => true
end
