# TODO: Test the `::features` on a subclass to ensure we scope correctly
module SpatialFeatures
  module ActMethod
    def has_spatial_features(options = {})
      unless acts_like?(:spatial_features)
        class_attribute :spatial_features_options
        self.spatial_features_options = {:make_valid => true}

        extend ClassMethods
        include InstanceMethods
        include FeatureImport

        has_many :features, lambda { extending FeaturesAssociationExtensions }, :as => :spatial_model, :dependent => :delete_all
        has_one :aggregate_feature, lambda { extending FeaturesAssociationExtensions }, :as => :spatial_model, :dependent => :delete

        scope :with_features, lambda { joins(:features).uniq }
        scope :without_features, lambda { joins("LEFT OUTER JOIN features ON features.spatial_model_type = '#{Utils.base_class(name)}' AND features.spatial_model_id = #{table_name}.id").where("features.id IS NULL") }

        scope :with_spatial_cache, lambda {|klass| joins(:spatial_caches).where(:spatial_caches => { :intersection_model_type =>  Utils.class_name_with_ancestors(klass) }).uniq }
        scope :without_spatial_cache, lambda {|klass| joins("LEFT OUTER JOIN #{SpatialCache.table_name} ON #{SpatialCache.table_name}.spatial_model_id = #{table_name}.id AND #{SpatialCache.table_name}.spatial_model_type = '#{Utils.base_class(name)}' and intersection_model_type IN ('#{Utils.class_name_with_ancestors(klass).join("','") }')").where("#{SpatialCache.table_name}.spatial_model_id IS NULL") }
        scope :with_stale_spatial_cache, lambda { joins(:spatial_caches).where("#{table_name}.features_hash != spatial_caches.features_hash").uniq } if has_spatial_features_hash?

        has_many :spatial_caches, :as => :spatial_model, :dependent => :delete_all, :class_name => 'SpatialCache'
        has_many :model_a_spatial_proximities, :as => :model_a, :class_name => 'SpatialProximity', :dependent => :delete_all
        has_many :model_b_spatial_proximities, :as => :model_b, :class_name => 'SpatialProximity', :dependent => :delete_all

        delegate :has_spatial_features_hash?, :has_features_area?, :to => self
      end

      self.spatial_features_options = self.spatial_features_options.merge(options)
    end
  end

  module ClassMethods
    def acts_like_spatial_features?
      true
    end

    def features_cache_key
      "#{name}/#{aggregate_features.cache_key}"
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
      type = base_class.to_s # Rails stores polymorphic foreign keys as the base class
      if all == unscoped
        Feature.where(:spatial_model_type => type)
      else
        Feature.where(:spatial_model_type => type, :spatial_model_id => all.unscope(:select))
      end
    end

    def aggregate_features
      type = base_class.to_s # Rails stores polymorphic foreign keys as the base class
      if all == unscoped
        AggregateFeature.where(:spatial_model_type => type)
      else
        AggregateFeature.where(:spatial_model_type => type, :spatial_model_id => all.unscope(:select))
      end
    end

    # Returns true if the model stores a hash of the features so we don't need to process the features if they haven't changed
    def has_spatial_features_hash?
      owner_class_has_loaded_column?('features_hash')
    end

    # Returns true if the model stores a cache of the features area
    def has_features_area?
      owner_class_has_loaded_column?('features_area')
    end

    def area_in_square_meters
      features.area
    end

    private

    def cached_within_buffer_scope(other, buffer_in_meters, options)
      options = options.reverse_merge(:columns => "#{table_name}.*")

      # Don't use the cache if it doesn't exist
      unless other.class.unscoped { other.spatial_cache_for?(Utils.class_of(self), buffer_in_meters) } # Unscope so if we're checking for same class intersections the scope doesn't affect this lookup
        return none.extending(UncachedResult)
      end

      scope = cached_spatial_join(other)
      scope = scope.select(options[:columns])
      scope = scope.where("spatial_proximities.distance_in_meters <= ?", buffer_in_meters) if buffer_in_meters
      scope = scope.select("spatial_proximities.distance_in_meters") if options[:distance]
      scope = scope.select("spatial_proximities.intersection_area_in_square_meters") if options[:intersection_area]
      return scope
    end

    def cached_spatial_join(other)
      other_class = Utils.base_class_of(other)
      self_class = Utils.base_class_of(self)

      joins <<~SQL
        INNER JOIN spatial_proximities
        ON (spatial_proximities.model_a_type = '#{self_class}' AND spatial_proximities.model_a_id = #{table_name}.id AND spatial_proximities.model_b_type = '#{other_class}' AND spatial_proximities.model_b_id IN (#{Utils.id_sql(other)}))
        OR (spatial_proximities.model_b_type = '#{self_class}' AND spatial_proximities.model_b_id = #{table_name}.id AND spatial_proximities.model_a_type = '#{other_class}' AND spatial_proximities.model_a_id IN (#{Utils.id_sql(other)}))
      SQL
    end

    def uncached_within_buffer_scope(other, buffer_in_meters, options)
      options = options.reverse_merge(:columns => "#{table_name}.*")

      scope = spatial_join(other, buffer_in_meters)
      scope = scope.select(options[:columns])

      scope = scope.select("ST_Distance(features.geom, other_features.geom) AS distance_in_meters") if options[:distance]
      scope = scope.select("ST_Area(ST_Intersection(ST_CollectionExtract(features.geom, 3), ST_CollectionExtract(other_features.geom, 3))) AS intersection_area_in_square_meters") if options[:intersection_area] # Use ST_CollectionExtract to avoid a segfault we've been seeing when intersecting certain geometry

      return scope
    end

    # Returns a scope that includes the features for this record as the table_alias and the features for other as other_alias
    # Performs a spatial intersection between the two sets of features, within the buffer distance given in meters
    def spatial_join(other, buffer = 0, table_alias = 'features', other_alias = 'other_features', geom = 'geom_lowres')
      scope = features_scope(self).select("#{geom} AS geom").select(:spatial_model_id)

      other_scope = features_scope(other).select("ST_Union(#{geom}) AS geom")
      return joins(%Q(INNER JOIN (#{scope.to_sql}) AS #{table_alias} ON #{table_alias}.spatial_model_id = #{table_name}.id))
            .joins(%Q(INNER JOIN (#{other_scope.to_sql}) AS #{other_alias}
                       ON NOT ST_IsEmpty(#{table_alias}.geom) -- Can't ST_DWithin empty geometry
                      AND NOT ST_IsEmpty(#{other_alias}.geom) -- Can't ST_DWithin empty geometry
                      AND ST_DWithin(#{table_alias}.geom, #{other_alias}.geom, #{buffer})))
    end

    def features_scope(other)
      scope = AggregateFeature
      scope = scope.where(:spatial_model_type => Utils.base_class_of(other).to_s)
      scope = scope.where(:spatial_model_id => other) unless Utils.class_of(other) == other
      return scope
    end

    def owner_class_has_loaded_column?(column_name)
      return false unless connected?
      return false unless table_exists?
      column_names.include? column_name
    end
  end

  module InstanceMethods
    def acts_like_spatial_features?
      true
    end

    def features_cache_key
      "#{self.class.name}/#{id}-#{has_spatial_features_hash? ? features_hash : aggregate_feature.cache_key}"
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
      if features.loaded?
        features.present?
      else
        features.exists?
      end
    end

    def intersects?(other)
      self.class.unscoped { self.class.intersecting(other).exists?(id) }
    end

    def total_intersection_area_percentage(klass)
      return 0.0 unless features_area_in_square_meters > 0

      ((total_intersection_area_in_square_meters(klass) / features_area_in_square_meters) * 100).round(1)
    end

    def features_area_in_square_meters
      @features_area_in_square_meters ||= aggregate_feature.area
    end

    def total_intersection_area_in_square_meters(other)
      other = other.intersecting(self) unless other.is_a?(ActiveRecord::Base)
      return features.area if spatial_cache_for?(other, 0) && SpatialProximity.between(self, other).where('intersection_area_in_square_meters >= ?', features.area).exists?
      return features.total_intersection_area_in_square_meters(other.features)
    end

    def spatial_cache_for?(other, buffer_in_meters)
      if cache = spatial_caches.between(self, Utils.class_of(other)).first
        return cache.intersection_cache_distance.nil? if buffer_in_meters.nil? # cache must be total if no buffer_in_meters
        return false if cache.stale? # cache must be for current features
        return true if cache.intersection_cache_distance.nil? # always good if cache is total

        return buffer_in_meters <= cache.intersection_cache_distance
      else
        return false
      end
    end
  end

  module FeaturesAssociationExtensions
    def area(options = {})
      if options[:cache] == false || !proxy_association.owner.class.has_features_area?
        area_in_square_meters
      else
        (proxy_association.owner.features_area || area_in_square_meters).to_f
      end
    end
  end
end
