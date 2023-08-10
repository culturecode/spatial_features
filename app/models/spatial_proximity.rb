class SpatialProximity < ActiveRecord::Base
  belongs_to :model_a, :polymorphic => true
  belongs_to :model_b, :polymorphic => true

  def self.between(scope1, scope2)
    where condition_sql(scope1, scope2, <<~SQL.squish)
      (#{SpatialFeatures::Utils.polymorphic_condition(scope1, 'model_a')} AND #{SpatialFeatures::Utils.polymorphic_condition(scope2, 'model_b')})
    SQL
  end

  def self.condition_sql(scope1, scope2, template, pattern_a = 'model_a', pattern_b = 'model_b')
    scope1_type = SpatialFeatures::Utils.base_class_of(scope1).to_s
    scope2_type = SpatialFeatures::Utils.base_class_of(scope2).to_s

    if scope1_type < scope2_type
      template
    elsif scope1_type > scope2_type
      template.gsub(pattern_a, 'model_c').gsub(pattern_b, pattern_a).gsub('model_c', pattern_b)
    else
      <<~SQL.squish
        (#{template}) OR (#{template.gsub(pattern_a, 'model_c').gsub(pattern_b, pattern_a).gsub('model_c', pattern_b)})
      SQL
    end
  end

  # Ensure the 'earliest' model is always model a
  def self.normalize
    unnormalized
      .update_all('model_a_type = model_b_type, model_b_type = model_a_type, model_a_id = model_b_id, model_b_id = model_a_id')
  end

  def self.unnormalized
    where('model_a_type > model_b_type OR (model_a_type = model_b_type AND model_a_id > model_b_id)')
  end
end
