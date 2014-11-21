module SpatialFeatures
  module ActMethod
    def has_spatial_features(options = {})
      has_many :features, :as => :spatial_model, :dependent => :delete_all
      scope :with_features, lambda { where(:id => Feature.select(:spatial_model_id).where(:spatial_model_type => name)) }
      scope :without_features, lambda { where.not(:id => Feature.select(:spatial_model_id).where(:spatial_model_type => name)) }

      has_many :spatial_cache, :as => :spatial_model, :dependent => :delete_all
      has_many :model_a_spatial_proximities, :as => :model_a, :class_name => 'SpatialProximity', :dependent => :delete_all
      has_many :model_b_spatial_proximities, :as => :model_b, :class_name => 'SpatialProximity', :dependent => :delete_all

      extend SpatialFeatures::ClassMethods
      include SpatialFeatures::InstanceMethods
    end
  end

  module ClassMethods
  	# Add methods to generate cache keys for a record or all records of this class
		# NOTE: features are never updated, only deleted and created, therefore we can
		# tell if they have changed by finding the maximum id and count instead of needing timestamps
		def features_cache_key
		  "#{name}/#{Feature.where(:spatial_model_type => self).maximum(:id)}-#{Feature.where(:spatial_model_type => self).count}"
		end

		def intersecting(other, options = {})
		  within_buffer(other, 0, options)
		end

		def within_buffer(other, buffer_in_meters = 0, options = {})
		  raise "Can't intersect with #{other} because it does not implement has_features" unless other.has_spatial_features?

		  if options[:cache] != false # CACHED
        return all.extending(UncachedRelation) unless other.spatial_cache_for?(self, buffer_in_meters) # Don't use the cache if it doesn't exist

		    scope = cached_spatial_join(other)
		      .select("#{table_name}.*, spatial_proximities.distance_in_meters, spatial_proximities.intersection_area_in_square_meters")

		    scope = scope.where("spatial_proximities.distance_in_meters <= ?", buffer_in_meters) if buffer_in_meters
		  else # NON-CACHED
		    scope = joins_features_for(other)
		      .select("#{table_name}.*")
		      .group("#{table_name}.#{primary_key}")

		    scope = scope.where('ST_DWithin(features_for.geog, features_for_other.geog, ?)', buffer_in_meters) if buffer_in_meters
		    scope = scope.select("MIN(ST_Distance(features_for.geog, features_for_other.geog)) AS distance_in_meters") if options[:distance]
		    scope = scope.select("SUM(ST_Area(ST_Intersection(features_for.geog, features_for_other.geog))) AS intersection_area_in_square_meters") if options[:intersection_area]
		  end

		  return scope
		end

		def polygons
		  Feature.polygons.where(:spatial_model_type => self.class)
		end

		def lines
		  Feature.lines.where(:spatial_model_type => self.class)
		end

		def points
		  Feature.points.where(:spatial_model_type => self.class)
		end

		def cached_spatial_join(other)
		  raise "Cannot use cached spatial join for the same class" if other.class.name == self.name

		  other_column = other.class.name < self.name ? :model_a : :model_b
		  self_column = other_column == :model_a ? :model_b : :model_a

		  joins("INNER JOIN spatial_proximities ON spatial_proximities.#{self_column}_type = '#{self}' AND spatial_proximities.#{self_column}_id = #{table_name}.id AND spatial_proximities.#{other_column}_type = '#{other.class}' AND spatial_proximities.#{other_column}_id = '#{other.id}'")
		end

		def joins_features_for(other, table_alias = 'features_for')
		  joins_features(table_alias)
		  .joins(%Q(INNER JOIN features "#{table_alias}_other" ON "#{table_alias}_other".spatial_model_type = '#{other.class.name}' AND "#{table_alias}_other".spatial_model_id = #{other.id}))
		end

		def joins_features(table_alias = 'features_for')
		  joins(%Q(INNER JOIN features "#{table_alias}" ON "#{table_alias}".spatial_model_type = '#{name}' AND "#{table_alias}".spatial_model_id = #{table_name}.id))
		end
  end

  module InstanceMethods
    def has_spatial_features?
      true
    end

    def features_cache_key
		  "#{self.class.name}/#{self.id}-#{features.maximum(:id)}-#{features.size}"
		end

		def polygons?
		  !features.polygons.empty?
		end

		def lines?
		  !features.lines.empty?
		end

		def points?
		  !features.points.empty?
		end

		def features?
		  features.present?
		end

		# Returns true if the model stores a hash of the features so we don't need to process the features if they haven't changed
		def has_spatial_features_hash?
		  respond_to?(:features_hash)
		end

		def intersects?(other)
		  self.class.intersecting(other).exists?(self)
		end

		def total_intersection_area_in_square_meters(klass, options = {})
		  self.class
		    .select(%Q(ST_Area(ST_Intersection(ST_Union(features_for.geog_lowres::geometry), ST_Union(features_for_other.geog_lowres::geometry))::geography) AS intersection_area_in_square_meters))
		    .joins(%Q(INNER JOIN features "features_for" ON "features_for".spatial_model_type = '#{self.class}' AND "features_for".spatial_model_id = #{self.class.table_name}.id))
		    .joins(%Q(INNER JOIN features "features_for_other" ON "features_for_other".spatial_model_type = '#{klass}'))
		    .where(:id => self.id)
		    .where('ST_DWithin(features_for.geog_lowres, features_for_other.geog_lowres, 0)')
		    .group("#{self.class.table_name}.id")
		    .first
		    .try(:intersection_area_in_square_meters) || 0
		end

		def total_intersection_area_in_hectares(klass)
		  Formatters::HECTARES.call(total_intersection_area_in_square_meters(klass))
		end

		def total_intersection_area_percentage(klass)
		  return 0.0 unless features_area_in_square_meters > 0

		  ((total_intersection_area_in_square_meters(klass) / features_area_in_square_meters) * 100).round(1)
		end

		def features_area_in_square_meters
		  @features_area_in_square_meters ||= features.sum('ST_Area(features.geog_lowres)')
		end

		def features_area_in_hectares
		  Formatters::HECTARES.call(features_area_in_square_meters)
		end

		def spatial_cache_for(klass)
		  spatial_cache.where(:intersection_model_type => klass).first
		end

		def spatial_cache_for?(klass, buffer_in_meters)
		  if cache = spatial_cache_for(klass)
		    return cache.cache_distance.nil? if buffer_in_meters.nil? # cache must be total if no buffer_in_meters
		    return true if cache.cache_distance.nil? # always good if cache is total

		    return buffer_in_meters <= cache.cache_distance
		  else
		    return false
		  end
		end
  end
end
