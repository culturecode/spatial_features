require 'digest/md5'
require 'fileutils'

module SpatialFeatures
  module FeatureImport
    extend ActiveSupport::Concern
    include QueuedSpatialProcessing

    included do
      extend ActiveModel::Callbacks
      define_model_callbacks :update_features
      spatial_features_options.reverse_merge!(:import => {}, :spatial_cache => [], :image_handlers => [])
    end

    module ClassMethods
      def update_features!(**options)
        find_each do |record|
          record.update_features!(**options)
        end
      end
    end

    def update_features!(skip_invalid: false, allow_blank: false, force: false, **options)
      options = options.reverse_merge(spatial_features_options)
      tmpdir = options.fetch(:tmpdir) { Dir.mktmpdir("ruby_spatial_features") }

      ActiveRecord::Base.transaction do
        imports = spatial_feature_imports(options[:import], options[:make_valid], options[:tmpdir])
        cache_key = Digest::MD5.hexdigest(imports.collect(&:cache_key).join)

        return if !force && features_cache_key_matches?(cache_key)

        run_callbacks :update_features do
          features = import_features(imports, skip_invalid)
          update_features_cache_key(cache_key)
          update_features_area

          if options[:spatial_cache].present? && options[:queue_spatial_cache]
            queue_update_spatial_cache(options.slice(:spatial_cache))
          else
            update_spatial_cache(options.slice(:spatial_cache))
          end

          if imports.present? && features.compact_blank.empty? && !allow_blank
            raise EmptyImportError, "No spatial features were found when updating"
          end
        end
      end

      return true
    rescue StandardError => e
      raise e if e.is_a?(EmptyImportError)

      if skip_invalid
        Rails.logger.warn "Error updating #{self.class} #{self.id}. #{e.message}"
        return nil
      else
        raise ImportError, e.message, e.backtrace
      end
    ensure
      FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir)
    end

    def update_features_cache_key(cache_key)
      return unless has_spatial_features_hash?
      self.features_hash = cache_key
      update_column(:features_hash, features_hash) unless new_record?
    end

    def update_features_area
      return unless has_attribute?(:features_area)
      self.features_area = features.area(:cache => false)
      update_column :features_area, features_area unless new_record?
    end

    def update_spatial_cache(options = {})
      options = options.reverse_merge(spatial_features_options)

      Array.wrap(options[:spatial_cache]).select(&:present?).each do |klass|
        SpatialFeatures.cache_record_proximity(self, klass.to_s.constantize)
      end
    end

    private

    def spatial_feature_imports(import_options, make_valid, tmpdir)
      import_options.flat_map do |data_method, importer_name|
        Array.wrap(send(data_method)).flat_map do |data|
          next unless data.present?
          spatial_importer_from_name(importer_name).create_all(data, :make_valid => make_valid, :tmpdir => tmpdir)
        end
      end.compact
    end

    def spatial_importer_from_name(importer_name)
      "SpatialFeatures::Importers::#{importer_name}".constantize
    end

    def handle_images(feature)
      return if feature.importable_image_paths.nil? || feature.importable_image_paths.empty?

      Array(spatial_features_options[:image_handlers]).each do |image_handler|
        image_handler_from_name(image_handler).call(feature, feature.importable_image_paths)
      end
    end

    def image_handler_from_name(handler_name)
      handler_name.to_s.constantize
    end

    def import_features(imports, skip_invalid)
      features.delete_all
      valid, invalid = Feature.defer_aggregate_refresh do
        Feature.without_caching_derivatives do
          imports.flat_map(&:features).partition do |feature|
            feature.spatial_model = self
            if feature.save
              handle_images(feature)
              true
            else
              false
            end
          end
        end
      end

      if persisted?
        features.reset # Reset the association cache because we've updated the features
        features.cache_derivatives
      else
        self.features = valid # Assign the features so when we save this record we update the foreign key on the features
        Feature.where(id: features).cache_derivatives
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

      valid
    end

    def features_cache_key_matches?(cache_key)
      has_spatial_features_hash? && cache_key == features_hash
    end
  end

  class ImportError < StandardError; end
end
