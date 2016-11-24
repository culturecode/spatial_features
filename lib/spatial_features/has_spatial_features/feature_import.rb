require 'digest/md5'

module SpatialFeatures
  module FeatureImport
    def update_features!(skip_invalid: false, **import_options)
      ActiveRecord::Base.transaction do
        imports = spatial_feature_imports(import_options)
        cache_key = Digest::MD5.hexdigest(imports.collect(&:cache_key).join)

        return if features_cache_key_matches?(cache_key)

        import_features(imports)
        validate_features!(imports, skip_invalid)
        set_features_cache_key(cache_key)

        return true
      end
    end

    private

    def spatial_feature_imports(options = {})
      spatial_features_options.fetch(:import, {}).collect do |data_method, importer_name|
        data = send(data_method)
        "SpatialFeatures::Importers::#{importer_name}".constantize.new(data, options) if data.present?
      end.compact
    end

    def import_features(imports)
      features.destroy_all
      features << imports.flat_map(&:features)
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
