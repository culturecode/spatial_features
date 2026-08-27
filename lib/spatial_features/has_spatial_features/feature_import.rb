require 'digest/md5'
require 'fileutils'

module SpatialFeatures
  module FeatureImport
    extend ActiveSupport::Concern
    include QueuedSpatialProcessing

    # Read by submitters as often as by staff, so it says what happened rather than which
    # method failed. Any per-file reasons are appended after it.
    EMPTY_IMPORT_MESSAGE = "No mapped areas could be imported.".freeze

    included do
      extend ActiveModel::Callbacks
      define_model_callbacks :update_features
      spatial_features_options.reverse_merge!(import: {}, spatial_cache: [], image_handlers: [])
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

      import_warnings = []

      ActiveRecord::Base.transaction do
        imports = spatial_feature_imports(options[:import], options[:make_valid], tmpdir)
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

          # Name the file each warning came from (e.g. `archive.zip/layer.kml`) so a multi-file
          # or multi-source import makes clear which file was affected. The file is kept apart
          # from the message so a reader can lay the two out separately.
          import_warnings = imports.flat_map do |import|
            import.warnings.map {|warning| { 'file' => import.source_identifier.presence, 'message' => warning } }
          end
          store_feature_update_warnings(import_warnings)

          if imports.present? && features.compact_blank.empty? && !allow_blank
            raise EmptyImportError, [EMPTY_IMPORT_MESSAGE, *import_warnings.map {|warning| warning.values.compact.join(': ') }].join(' ')
          end
        end
      end

      return true
    rescue StandardError => e
      # The transaction that recorded them has rolled back, so without this a failed import
      # explains itself only through the exception message — which reaches a reader as one
      # unbroken paragraph, and not at all once the job is cleared.
      store_feature_update_warnings(import_warnings) if persisted? && import_warnings.present?

      raise e if e.is_a?(EmptyImportError)

      if skip_invalid
        Rails.logger.warn "Error updating #{self.class} #{self.id}. #{e.message}"
        return nil
      elsif ENCODING_ERROR.match?(e.message)
        raise ImportEncodingError,
              "This file contains text in an unsupported character encoding (#{e.message}). " \
              "Text must be encoded as UTF-8.",
              e.backtrace
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
      self.features_area = features.area(cache: false)
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
      import_options.flat_map do |data_method, configuration|
        case configuration
        when Hash
          importer_name = configuration.fetch(:name)
          options = configuration.except(:name)
        else
          importer_name = configuration
          options = {}
        end

        Array.wrap(send(data_method)).each_with_index.flat_map do |data, index|
          next unless data.present?

          source_tmpdir = spatial_import_tmpdir(tmpdir, data_method, index)

          begin
            spatial_importer_from_name(importer_name).create_all(data, **options, make_valid: make_valid, tmpdir: source_tmpdir)
          rescue ImportError, Zip::Error, Errno::ENOENT => e
            # One unreadable file must not discard the geometry of the files uploaded
            # beside it. Stand in for it so the rest of the import proceeds and the
            # reason reaches the user as a warning against that file.
            Importers::UnreadableFile.new(data, e, **options, make_valid: make_valid, tmpdir: source_tmpdir)
          end
        end
      end.compact
    end

    # Every source file unpacks into its own directory. Two KMZs on one record both hold a
    # `doc.kml`, so sharing one tmpdir means the second extraction collides with the first
    # and the whole import dies on an archive that is perfectly fine.
    def spatial_import_tmpdir(tmpdir, data_method, index)
      ::File.join(tmpdir, "#{data_method}-#{index}").tap {|dir| FileUtils.mkdir_p(dir) }
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
          imports.flat_map {|import| features_from(import) }.partition do |feature|
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

    # Parse failures surface lazily, when an importer's features are first read (e.g. a
    # shapefile archive missing its `.shx`), so they need the same containment as a file
    # that couldn't be opened at all: record the reason against that source and keep going.
    def features_from(import)
      import.features
    rescue ImportError => e
      import.warnings << e.message
      []
    end

    def features_cache_key_matches?(cache_key)
      has_spatial_features_hash? && cache_key == features_hash
    end
  end

  ENCODING_ERROR = /invalid byte sequence/i.freeze
end
