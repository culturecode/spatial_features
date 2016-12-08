module SpatialFeatures
  mattr_accessor :default_cache_buffer_in_meters
  self.default_cache_buffer_in_meters = 100

  def self.update_proximity(*klasses)
    klasses.permutation(2).each do |klass, clazz|
      klass.without_spatial_cache(clazz).find_each do |record|
        cache_record_proximity(record, clazz)
      end
    end

    klasses.each do |klass|
      update_spatial_cache(klass)
    end
  end

  def self.update_spatial_cache(scope)
    scope.with_stale_spatial_cache.includes(:spatial_cache).find_each do |record|
      record.spatial_cache.each do |spatial_cache|
        cache_record_proximity(record, spatial_cache.intersection_model_type) if spatial_cache.stale?
      end
    end
  end

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
    record.spatial_cache.where(:intersection_model_type => klass).delete_all
    SpatialProximity.where(:model_a_type => record.class, :model_a_id => record.id, :model_b_type => klass).delete_all
    SpatialProximity.where(:model_b_type => record.class, :model_b_id => record.id, :model_a_type => klass).delete_all
  end

  def self.create_spatial_proximities(record, klass)
    klass = klass.to_s.constantize
    klass_record = klass.new
    model_a, model_b = record.class.to_s < klass.to_s ? [record, klass_record] : [klass_record, record]

    scope = klass.within_buffer(record, default_cache_buffer_in_meters, :columns => :id, :intersection_area => true, :distance => true, :cache => false)
    results = klass.connection.select_rows(scope.to_sql)

    results.each do |id, distance, area|
      klass_record.id = id
      SpatialProximity.create! do |proximity|
        # Set id and type instead of model to avoid autosaving the klass_record
        proximity.model_a_id = model_a.id
        proximity.model_a_type = model_a.class
        proximity.model_b_id = model_b.id
        proximity.model_b_type = model_b.class
        proximity.distance_in_meters = distance
        proximity.intersection_area_in_square_meters = area
      end
    end
  end

  def self.create_spatial_cache(model, klass)
    SpatialCache.create! do |cache|
      cache.spatial_model               = model
      cache.intersection_model_type     = klass
      cache.intersection_cache_distance = default_cache_buffer_in_meters
      cache.features_hash               = model.features_hash if model.has_spatial_features_hash?
    end
  end
end
