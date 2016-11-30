require 'digest/md5'

module SpatialFeatures
  module FeatureImport
    extend ActiveSupport::Concern

    included do
      extend ActiveModel::Callbacks
      define_model_callbacks :update_features
    end

    def update_features!(skip_invalid: false, options: {})
      options = options.reverse_merge(spatial_features_options).reverse_merge(:import => {})

      ActiveRecord::Base.transaction do
        imports = spatial_feature_imports(options[:import], options[:make_valid])
        cache_key = Digest::MD5.hexdigest(imports.collect(&:cache_key).join)

        return if features_cache_key_matches?(cache_key)

        run_callbacks :update_features do
          import_features(imports)
          validate_features!(imports, skip_invalid)
          set_features_cache_key(cache_key)
        end

        return true
      end
    end

    private

    def spatial_feature_imports(import_options, make_valid)
      import_options.collect do |data_method, importer_name|
        data = send(data_method)
        "SpatialFeatures::Importers::#{importer_name}".constantize.new(data, :make_valid => make_valid) if data.present?
      end.compact
    end

    def import_features(imports)
      self.features.delete_all
      self.features = imports.flat_map(&:features)
    end

    def validate_features!(imports, skip_invalid = false)
      invalid = features.select {|feature| feature.errors.present? }
      features.destroy(invalid)

      return if skip_invalid

      errors = imports.flat_map(&:errors)
      invalid.each do |feature|
        errors << "Feature #{feature.name}: #{feature.errors.full_messages.to_sentence}"
      end

      if errors.present?
        raise ImportError, "Error updating #{self.class} #{self.id}. #{errors.to_sentence}"
      end
    end

    def features_cache_key_matches?(cache_key)
      has_spatial_features_hash? && cache_key == features_hash
    end

    def set_features_cache_key(cache_key)
      return unless has_spatial_features_hash?
      self.features_hash = cache_key
      update_column(:features_hash, cache_key) unless new_record?
    end
  end

  class ImportError < StandardError; end
end
