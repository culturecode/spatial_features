require 'digest/md5'

module SpatialFeatures
  module FeatureImport
    def update_features!(skip_invalid: false, **import_options)
      ActiveRecord::Base.transaction do
        imports = spatial_feature_imports(import_options)
        cache_key = Digest::MD5.hexdigest(imports.collect(&:cache_key).join)

        if has_spatial_features_hash? && cache_key != features_hash
          import_features(imports)
          validate_features!(skip_invalid)
          update_attributes(:features_hash => cache_key)
        elsif !has_spatial_features_hash?
          import_features(imports)
          validate_features!(skip_invalid)
        end
      end
    end

    private

    def spatial_feature_imports(options = {})
      spatial_features_options.fetch(:import, {}).collect do |data_method, importer_name|
        "SpatialFeatures::Importers::#{importer_name}".constantize.new(send(data_method), options)
      end
    end

    def import_features(imports)
      features.destroy_all
      features << imports.flat_map(&:features)
    end

    def validate_features!(skip_invalid = false)
      invalid = features.select {|feature| feature.errors.present? }
      features.destroy(invalid)

      return if skip_invalid
      errors = invalid.collect do |feature|
        "Feature #{feature.name}: #{feature.errors.full_messages.to_sentence}"
      end

      if errors.present?
        raise UpdateError, "Error updating #{self.class} #{self.id}. #{errors.to_sentence}"
      end
    end

    class UpdateError < StandardError; end
  end
end
