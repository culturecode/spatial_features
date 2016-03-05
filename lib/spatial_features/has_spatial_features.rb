module SpatialFeatures
  module ActMethod
    def has_spatial_features(options = {})
      extend ClassMethods
      include InstanceMethods

      has_many :features, lambda { extending FeaturesAssociationExtensions }, :as => :spatial_model, :dependent => :delete_all

      scope :with_features, lambda { joins(:features).uniq }
      scope :without_features, lambda { joins("LEFT OUTER JOIN features ON features.spatial_model_type = '#{name}' AND features.spatial_model_id = #{table_name}.id").where("features.id IS NULL") }

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
        # Don't use the cache if it doesn't exist
        return all.extending(UncachedRelation) unless other.spatial_cache_for?(class_for(self), buffer_in_meters)

        scope = cached_spatial_join(other).select("#{table_name}.*")
        scope = scope.where("spatial_proximities.distance_in_meters <= ?", buffer_in_meters) if buffer_in_meters
        scope = scope.select("spatial_proximities.distance_in_meters") if options[:distance]
        scope = scope.select("spatial_proximities.intersection_area_in_square_meters") if options[:intersection_area]
      else # NON-CACHED
        scope = joins_features_for(other).select("#{table_name}.*").group("#{table_name}.#{primary_key}")
        scope = scope.where('ST_DWithin(features_for.geom, features_for_other.geom, ?)', buffer_in_meters) if buffer_in_meters
        scope = scope.select("MIN(ST_Distance(features_for.geom, features_for_other.geom)) AS distance_in_meters") if options[:distance]
        scope = scope.select("ST_Area(ST_Intersection(ST_UNION(features_for.geom), ST_UNION(features_for_other.geom))) AS intersection_area_in_square_meters") if options[:intersection_area]
      end

      return scope
    end

    def covering(other)
      scope = joins_features_for(other).select("#{table_name}.*").group("#{table_name}.#{primary_key}")
      scope = scope.where('ST_Covers(features_for.geom, features_for_other.geom)')

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
      if all == unscoped.all
        Feature.where(:spatial_model_type => self)
      else
        Feature.where(:spatial_model_type => self, :spatial_model_id => all)
      end
    end

    # Returns a scope that includes the features for this record as the table_alias and the features for other as #{table_alias}_other
    # Can be used to perform spatial calculations on the relationship between the two sets of features
    def joins_features_for(other, table_alias = 'features_for')
      joins_features(table_alias)
        .joins_features("#{table_alias}_other", class_for(other), spatial_model_id = ids_sql_for(other))
    end

    # Returns a scope that includes the features for this record as the table_alias
    # Default arguments can be overridden to include features for a different set of records
    def joins_features(table_alias = 'features_for', spatial_model_type = name, spatial_model_id = "#{table_name}.id")
      joins %Q(INNER JOIN features "#{table_alias}"
               ON "#{table_alias}".spatial_model_type = '#{spatial_model_type}'
               AND "#{table_alias}".spatial_model_id IN (#{spatial_model_id}))
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
      scope = self.class.where(:id => self.id)
                .joins_features_for(other)
                .where('ST_DWithin(features_for.geog_lowres, features_for_other.geog_lowres, 0)')
                .select('ST_Area(ST_Intersection(ST_Union(features_for.geog_lowres::geometry), ST_Union(features_for_other.geog_lowres::geometry))::geography) AS intersection_area_in_square_meters')
                .reorder(nil) # Avoid default scopes that order on columns that aren't present

      self.class.connection.select_value(scope).to_f
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
        connection.select_value(all.select('ST_Area(ST_UNION(geom))')).try(:to_f)
      else
        proxy_association.owner.features_area
      end
    end
  end
end
