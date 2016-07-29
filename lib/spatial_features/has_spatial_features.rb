module SpatialFeatures
  module ActMethod
    def has_spatial_features(options = {})
      extend ClassMethods
      include InstanceMethods

      has_many :features, lambda { extending FeaturesAssociationExtensions }, :as => :spatial_model, :dependent => :delete_all

      scope :with_features, lambda { joins(:features).uniq }
      scope :without_features, lambda { joins("LEFT OUTER JOIN features ON features.spatial_model_type = '#{name}' AND features.spatial_model_id = #{table_name}.id").where("features.id IS NULL") }

      scope :with_stale_spatial_cache, lambda { joins(:spatial_cache).where("#{table_name}.features_hash != spatial_caches.features_hash").uniq } if has_spatial_features_hash?

      has_many :spatial_cache, :as => :spatial_model, :dependent => :delete_all
      has_many :model_a_spatial_proximities, :as => :model_a, :class_name => 'SpatialProximity', :dependent => :delete_all
      has_many :model_b_spatial_proximities, :as => :model_b, :class_name => 'SpatialProximity', :dependent => :delete_all

      after_save :update_features_area, :if => :features_hash_changed? if has_features_area? && has_spatial_features_hash?

      delegate :has_spatial_features_hash?, :has_features_area?, :to => self
    end
  end

  module ClassMethods
    # Add methods to generate cache keys for a record or all records of this class
    # NOTE: features are never updated, only deleted and created, therefore we can
    # tell if they have changed by finding the maximum id and count instead of needing timestamps
    def features_cache_key
      # Do two separate queries because it is much faster for some reason
      "#{name}/#{features.maximum(:id)}-#{features.count}"
    end

    def intersecting(other, options = {})
      within_buffer(other, 0, options)
    end

    def within_buffer(other, buffer_in_meters = 0, options = {})
      return none if other.is_a?(ActiveRecord::Base) && other.new_record?

      # Cache only works on single records, not scopes.
      # This is because the cached intersection_area doesn't account for overlaps between the features in the scope.
      if options[:cache] != false && other.is_a?(ActiveRecord::Base)
        cached_within_buffer_scope(other, buffer_in_meters, options)
      else
        uncached_within_buffer_scope(other, buffer_in_meters, options)
      end
    end

    def covering(other)
      scope = joins_features_for(other).select("#{table_name}.*").group("#{table_name}.#{primary_key}")
      scope = scope.where('ST_Covers(features.geom, features_for_other.geom)')

      return scope
    end

    def polygons
      features.polygons
    end

    def lines
      features.lines
    end

    def points
      features.points
    end

    def features
      if all == unscoped
        Feature.where(:spatial_model_type => self)
      else
        Feature.where(:spatial_model_type => self, :spatial_model_id => all.unscope(:select))
      end
    end

    # Returns a scope that includes the features for this record as the table_alias and the features for other as #{table_alias}_other
    # Can be used to perform spatial calculations on the relationship between the two sets of features
    def joins_features_for(other, table_alias = 'features_for')
      joins(:features).joins(%Q(INNER JOIN (#{other_features_union(other).to_sql}) AS "#{table_alias}_other" ON true))
    end

    def other_features_union(other)
      scope = Feature.select('ST_Union(geom) AS geom').where(:spatial_model_type => class_for(other))
      scope = scope.where(:spatial_model_id => other) unless class_for(other) == other
      return scope
    end

    # Returns true if the model stores a hash of the features so we don't need to process the features if they haven't changed
    def has_spatial_features_hash?
      column_names.include? 'features_hash'
    end

    # Returns true if the model stores a cache of the features area
    def has_features_area?
      column_names.include? 'features_area'
    end

    def area_in_square_meters
      features.area_in_square_meters
    end

    private

    def cached_within_buffer_scope(other, buffer_in_meters, options)
      # Don't use the cache if it doesn't exist
      return all.extending(UncachedRelation) unless other.spatial_cache_for?(class_for(self), buffer_in_meters)

      scope = cached_spatial_join(other).select("#{table_name}.*")
      scope = scope.where("spatial_proximities.distance_in_meters <= ?", buffer_in_meters) if buffer_in_meters
      scope = scope.select("spatial_proximities.distance_in_meters") if options[:distance]
      scope = scope.select("spatial_proximities.intersection_area_in_square_meters") if options[:intersection_area]
      return scope
    end

    def uncached_within_buffer_scope(other, buffer_in_meters, options)
      scope = joins_features_for(other).select("#{table_name}.*")
      scope = scope.where('ST_Intersects(features.geom, features_for_other.geom)') if buffer_in_meters == 0 # Optimize the 0 buffer case, ST_DWithin was slower in testing
      scope = scope.where('ST_DWithin(features.geom, features_for_other.geom, ?)', buffer_in_meters) if buffer_in_meters.to_f > 0

      # Ensure records with multiple features don't appear multiple times
      if options[:distance] || options[:intersection_area]
        scope = scope.group("#{table_name}.#{primary_key}") # Aggregate functions require grouping
      else
        scope = scope.distinct
      end

      scope = scope.select("MIN(ST_Distance(features.geom, features_for_other.geom)) AS distance_in_meters") if options[:distance]
      scope = scope.select("ST_Area(ST_Intersection(ST_UNION(features.geom), ST_UNION(features_for_other.geom))) AS intersection_area_in_square_meters") if options[:intersection_area]
      return scope
    end

    def cached_spatial_join(other)
      other_class = class_for(other)

      raise "Cannot use cached spatial join for the same class" if self == other_class

      other_column = other_class.name < self.name ? :model_a : :model_b
      self_column = other_column == :model_a ? :model_b : :model_a

      joins("INNER JOIN spatial_proximities ON spatial_proximities.#{self_column}_type = '#{self}' AND spatial_proximities.#{self_column}_id = #{table_name}.id AND spatial_proximities.#{other_column}_type = '#{other_class}' AND spatial_proximities.#{other_column}_id IN (#{ids_sql_for(other)})")
    end

    # Returns the class for the given, class, scope, or record
    def class_for(other)
      case other
      when ActiveRecord::Base
        other.class
      when ActiveRecord::Relation
        other.klass
      else
        other
      end
    end

    def ids_sql_for(other)
      if other.is_a?(ActiveRecord::Base)
        other.id || '0'
      else
        other.unscope(:select).select(:id).to_sql
      end
    end
  end

  module InstanceMethods
    def has_spatial_features?
      true
    end

    def features_cache_key
      max_id, count = features.pluck("MAX(id), COUNT(*)").first
      "#{self.class.name}/#{self.id}-#{max_id}-#{count}"
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

    def covers?(other)
      self.class.covering(other).exists?(self)
    end

    def intersects?(other)
      self.class.intersecting(other).exists?(self)
    end

    def total_intersection_area_percentage(klass)
      return 0.0 unless features_area_in_square_meters > 0

      ((total_intersection_area_in_square_meters(klass) / features_area_in_square_meters) * 100).round(1)
    end

    def features_area_in_square_meters
      @features_area_in_square_meters ||= features.area
    end

    def total_intersection_area_in_square_meters(other)
      other = other.intersecting(self) unless other.is_a?(ActiveRecord::Base)
      return features.total_intersection_area_in_square_meters(other.features)
    end

    def spatial_cache_for?(klass, buffer_in_meters)
      if cache = spatial_cache_for(klass)
        return cache.intersection_cache_distance.nil? if buffer_in_meters.nil? # cache must be total if no buffer_in_meters
        return false if cache.stale? # cache must be for current features
        return true if cache.intersection_cache_distance.nil? # always good if cache is total

        return buffer_in_meters <= cache.intersection_cache_distance
      else
        return false
      end
    end

    def spatial_cache_for(klass)
      spatial_cache.where(:intersection_model_type => klass).first
    end

    def update_features_area
      update_column :features_area, features.area(:cache => false)
    end
  end

  module FeaturesAssociationExtensions
    def area(options = {})
      if options[:cache] == false || !proxy_association.owner.class.has_features_area?
        pluck('ST_Area(ST_UNION(geom))').first.to_f
      else
        proxy_association.owner.features_area
      end
    end
  end
end
