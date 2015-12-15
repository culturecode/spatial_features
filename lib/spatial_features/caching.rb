module SpatialFeatures
  mattr_accessor :default_cache_buffer_in_meters
  self.default_cache_buffer_in_meters = 100

  # Create or update the spatial cache of a spatial class in relation to another
  # NOTE: Arguments are order independent, so their names do not reflect the _a _b
  # naming scheme used in other cache methods
  def self.cache_proximity(*klasses)
    klasses.combination(2).each do |klass, clazz|
      clear_cache(klass, clazz)

      klass.find_each do |record|
        create_spatial_proximities(record, clazz)
        create_spatial_cache(record, clazz)
      end

      clazz.find_each do |record|
        create_spatial_cache(record, klass)
      end
    end
  end

  # Create or update the spatial cache of a single record in relation to another spatial class
  def self.cache_record_proximity(record, klass)
    clear_record_cache(record, klass)
    create_spatial_proximities(record, klass)
    create_spatial_cache(record, klass)
  end

  # Delete all cache entries relating klass to clazz
  def self.clear_cache(klass = nil, clazz = nil)
    if klass.blank? && clazz.blank?
      SpatialCache.delete_all
      SpatialProximity.delete_all
    else
      SpatialCache.where(:spatial_model_type => klass, :intersection_model_type => clazz).delete_all
      SpatialCache.where(:spatial_model_type => clazz, :intersection_model_type => klass).delete_all
      SpatialProximity.where(:model_a_type => klass, :model_b_type => clazz).delete_all
      SpatialProximity.where(:model_a_type => clazz, :model_b_type => klass).delete_all
    end
  end

  def self.clear_record_cache(record, klass)
    record.spatial_cache.where(:intersection_model_type => klass.name).delete_all
    SpatialProximity.where(:model_a_type => record.class.name, :model_a_id => record.id, :model_b_type => klass.name).delete_all
    SpatialProximity.where(:model_b_type => record.class.name, :model_b_id => record.id, :model_a_type => klass.name).delete_all
  end

  def self.create_spatial_proximities(record, klass)
    record_is_a = record.class.name < klass.name

    scope = klass.within_buffer(record, default_cache_buffer_in_meters, :intersection_area => true, :distance => true, :cache => false)
    scope.find_each do |klass_record|
      SpatialProximity.create! do |proximity|
        proximity.model_a                            = record_is_a ? record : klass_record
        proximity.model_b                            = record_is_a ? klass_record : record
        proximity.distance_in_meters                 = klass_record.distance_in_meters
        proximity.intersection_area_in_square_meters = klass_record.intersection_area_in_square_meters
      end
    end
  end

  def self.create_spatial_cache(model, klass)
    SpatialCache.create! do |cache|
      cache.spatial_model               = model
      cache.intersection_model_type     = klass.name
      cache.intersection_cache_distance = default_cache_buffer_in_meters
      cache.features_hash               = model.features_hash if model.has_spatial_features_hash?
    end
  end
end
