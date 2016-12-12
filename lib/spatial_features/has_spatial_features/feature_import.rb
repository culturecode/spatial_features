require 'digest/md5'

module SpatialFeatures
  module FeatureImport
    extend ActiveSupport::Concern

    included do
      extend ActiveModel::Callbacks
      define_model_callbacks :update_features
      spatial_features_options.reverse_merge!(:import => {}, spatial_cache: [])
      after_save :update_features_area, :if => :features_changed?, :unless => :features_area_changed?
    end

    module ClassMethods
      def update_features!(skip_invalid: false)
        find_each do |record|
          record.update_features!(skip_invalid: skip_invalid)
        end
      end
    end

    def update_features!(skip_invalid: false, **options)
      options = options.reverse_merge(spatial_features_options)

      ActiveRecord::Base.transaction do
        imports = spatial_feature_imports(options[:import], options[:make_valid])
        cache_key = Digest::MD5.hexdigest(imports.collect(&:cache_key).join)

        return if features_cache_key_matches?(cache_key)

        run_callbacks :update_features do
          import_features(imports, skip_invalid)
          update_features_cache_key(cache_key)
          update_features_area
          update_spatial_cache
        end

        return true
      end
    end

    def features_will_change!(*)
      @features_changed = true
    end

    def features_changed?
      !!@features_changed
    end

    private

    def spatial_feature_imports(import_options, make_valid)
      import_options.collect do |data_method, importer_name|
        data = send(data_method)
        spatial_importer_from_name(importer_name).new(data, :make_valid => make_valid) if data.present?
      end.compact
    end

    def spatial_importer_from_name(importer_name)
      "SpatialFeatures::Importers::#{importer_name}".constantize
    end

    def import_features(imports, skip_invalid)
      self.features.delete_all
      valid, invalid = imports.flat_map(&:features).partition do |feature|
        feature.spatial_model = self
        feature.save
      end

      errors = imports.flat_map(&:errors)
      invalid.each do |feature|
        errors << "Feature #{feature.name}: #{feature.errors.full_messages.to_sentence}"
      end

      if skip_invalid && errors.present?
        Rails.logger.warn "Error updating #{self.class} #{self.id}. #{errors.to_sentence}"
      elsif errors.present?
        raise ImportError, "Error updating #{self.class} #{self.id}. #{errors.to_sentence}"
      end

      self.features = valid
    end

    def features_cache_key_matches?(cache_key)
      has_spatial_features_hash? && cache_key == features_hash
    end

    def update_features_cache_key(cache_key)
      return unless has_spatial_features_hash?
      self.features_hash = cache_key
      update_column(:features_hash, features_hash) unless new_record?
    end

    def update_features_area
      return unless has_spatial_features_hash?
      self.features_area = features.area(:cache => false)
      update_column :features_area, features_area unless new_record?
    end

    def update_spatial_cache
      Array.wrap(spatial_features_options[:spatial_cache]).each do |klass|
        SpatialFeatures.cache_record_proximity(self, klass.to_s.constantize)
      end
    end
  end

  class ImportError < StandardError; end
end
