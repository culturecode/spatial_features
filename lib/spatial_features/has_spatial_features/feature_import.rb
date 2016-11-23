module SpatialFeatures
  module FeatureImport
    def update_features!(skip_invalid: false, **import_options)
      ActiveRecord::Base.transaction do
        each_spatial_feature_import(import_options) do |import|
          if has_spatial_features_hash? && import.cache_key != features_hash
            replace_features(import, skip_invalid)
            update_attributes(:features_hash => import.cache_key)
          elsif !has_spatial_features_hash?
            replace_features(import, skip_invalid) and return true
          end
        end
      end
    end

    private

    def each_spatial_feature_import(options)
      spatial_features_options.fetch(:import, {}).each do |importer_name, data_method|
        yield "SpatialFeatures::Importers::#{importer_name.to_s.camelize}".constantize.new(send(data_method), options)
      end
    end

    def replace_features(import, skip_invalid)
      features.destroy_all
      binding.pry
      self.features = import.features

      errors = import.errors.dup
      import.features.each do |feature|
        errors << "Feature #{feature.name}: #{feature.errors.full_messages.to_sentence}" if feature.errors.present?
      end

      if errors.present? && !skip_invalid
        raise UpdateError, "Error updating #{self.class} #{self.id}. #{errors.to_sentence}"
      end
    end

    class UpdateError < StandardError; end
  end
end
