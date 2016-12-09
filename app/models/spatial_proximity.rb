class SpatialProximity < ActiveRecord::Base
  belongs_to :model_a, :polymorphic => true
  belongs_to :model_b, :polymorphic => true

  def self.between(scope_1, scope_2)
    where <<-SQL.squish
      (#{SpatialFeatures::Utils.polymorphic_condition(scope_1, 'model_a')} AND #{SpatialFeatures::Utils.polymorphic_condition(scope_2, 'model_b')}) OR
      (#{SpatialFeatures::Utils.polymorphic_condition(scope_2, 'model_a')} AND #{SpatialFeatures::Utils.polymorphic_condition(scope_1, 'model_b')})
    SQL
  end
end
