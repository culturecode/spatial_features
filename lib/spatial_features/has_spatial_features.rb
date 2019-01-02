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

        scope :with_features, lambda { joins(:features).uniq }
        scope :without_features, lambda { joins("LEFT OUTER JOIN features ON features.spatial_model_type = '#{name}' AND features.spatial_model_id = #{table_name}.id").where("features.id IS NULL") }

        scope :with_spatial_cache, lambda {|klass| joins(:spatial_caches).where(:spatial_caches => { :intersection_model_type =>  klass }).uniq }
        scope :without_spatial_cache, lambda {|klass| joins("LEFT OUTER JOIN #{SpatialCache.table_name} ON #{SpatialCache.table_name}.spatial_model_id = #{table_name}.id AND #{SpatialCache.table_name}.spatial_model_type = '#{name}' and intersection_model_type = '#{klass}'").where("#{SpatialCache.table_name}.spatial_model_id IS NULL") }
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

    # Add methods to generate cache keys for a record or all records of this class
    # NOTE: features are never updated, only deleted and created, therefore we can
    # tell if they have changed by finding the maximum id and count instead of needing timestamps
    def features_cache_key
      # Do two separate queries because it is much faster for some reason
      "#{name}/#{features.cache_key}"
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
      type = base_class # Rails stores polymorphic foreign keys as the base class
      if all == unscoped
        Feature.where(:spatial_model_type => type)
      else
        Feature.where(:spatial_model_type => type, :spatial_model_id => all.unscope(:select))
      end
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
      options = options.reverse_merge(:columns => "#{table_name}.*")

      # Don't use the cache if it doesn't exist
      return none.extending(UncachedResult) unless other.spatial_cache_for?(Utils.class_of(self), buffer_in_meters)

      scope = cached_spatial_join(other)
      scope = scope.select(options[:columns])
      scope = scope.where("spatial_proximities.distance_in_meters <= ?", buffer_in_meters) if buffer_in_meters
      scope = scope.select("spatial_proximities.distance_in_meters") if options[:distance]
      scope = scope.select("spatial_proximities.intersection_area_in_square_meters") if options[:intersection_area]
      return scope
    end

    def cached_spatial_join(other)
      other_class = Utils.class_of(other)

      raise "Cannot use cached spatial join for the same class" if self == other_class

      other_column = other_class.name < self.name ? :model_a : :model_b
      self_column = other_column == :model_a ? :model_b : :model_a

      joins("INNER JOIN spatial_proximities ON spatial_proximities.#{self_column}_type = '#{self}' AND spatial_proximities.#{self_column}_id = #{table_name}.id AND spatial_proximities.#{other_column}_type = '#{other_class}' AND spatial_proximities.#{other_column}_id IN (#{Utils.id_sql(other)})")
    end

    def uncached_within_buffer_scope(other, buffer_in_meters, options)
      options = options.reverse_merge(:columns => "#{table_name}.*")

      scope = spatial_join(other, buffer_in_meters)
      scope = scope.select(options[:columns])

      # Ensure records with multiple features don't appear multiple times
      if options[:distance] || options[:intersection_area]
        scope = scope.group("#{table_name}.#{primary_key}") # Aggregate functions require grouping
      else
        scope = scope.distinct
      end

      scope = scope.select("MIN(ST_Distance(features.geom, other_features.geom)) AS distance_in_meters") if options[:distance]
      scope = scope.select("ST_Area(ST_UNION(ST_Intersection(ST_CollectionExtract(features.geom, 3), ST_CollectionExtract(other_features.geom, 3)))) AS intersection_area_in_square_meters") if options[:intersection_area]
      return scope
    end

    # Returns a scope that includes the features for this record as the table_alias and the features for other as other_alias
    # Performs a spatial intersection between the two sets of features, within the buffer distance given in meters
    def spatial_join(other, buffer = 0, table_alias = 'features', other_alias = 'other_features', geom = 'geom_lowres')
      scope = features_scope(self).select("#{geom} AS geom").select(:spatial_model_id)

      other_scope = features_scope(other)
      other_scope = other_scope.select("ST_Union(#{geom}) AS geom").select("ST_Buffer(ST_Union(#{geom}), #{buffer.to_i}) AS buffered_geom")

      return joins(%Q(INNER JOIN (#{scope.to_sql}) AS #{table_alias} ON #{table_alias}.spatial_model_id = #{table_name}.id))
            .joins(%Q(INNER JOIN (#{other_scope.to_sql}) AS #{other_alias} ON ST_Intersects(#{table_alias}.geom, #{other_alias}.buffered_geom)))
    end

    def features_scope(other)
      scope = Feature
      scope = scope.where(:spatial_model_type => Utils.class_of(other))
      scope = scope.where(:spatial_model_id => other) unless Utils.class_of(other) == other
      return scope
    end
  end

  module InstanceMethods
    def acts_like_spatial_features?
      true
    end

    def features_cache_key
      "#{self.class.name}/#{self.id}-#{features.cache_key}"
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
      return features.area if spatial_cache_for?(other, 0) && SpatialProximity.between(self, other).where('intersection_area_in_square_meters >= ?', features.area).exists?
      return features.total_intersection_area_in_square_meters(other.features)
    end

    def spatial_cache_for?(other, buffer_in_meters)
      if cache = spatial_caches.between(self, SpatialFeatures::Utils.class_of(other)).first
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
