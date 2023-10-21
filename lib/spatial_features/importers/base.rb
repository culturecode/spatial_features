require 'digest/md5'

module SpatialFeatures
  module Importers
    class Base
      attr_reader :errors
      attr_accessor :source_identifier # An identifier for the source of the features. Used to differentiate groups of features on the spatial model.

      def initialize(data, make_valid: false, tmpdir: nil, source_identifier: nil)
        @make_valid = make_valid
        @data = data
        @errors = []
        @tmpdir = tmpdir
        @source_identifier = source_identifier
      end

      def features
        @features ||= build_features
      end

      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(@data)
      end

      # factory method that should always be used instead of `new` when creating importers
      # returns an array of Importer::* objects
      def self.create_all(data, **options)
        [new(data, **options)]
      end

      private

      def build_features
        new_features = []

        each_record do |record|
          begin
            new_features << build_feature(record)
          rescue => e
            @errors << e.message
          end
        end

        return new_features
      end

      def each_record(&block)
        raise NotImplementedError, 'Subclasses should implement this method and yield objects that can be passed to #build_feature'
      end

      def build_feature(record)
        importable_image_paths = record.importable_image_paths if record.respond_to?(:importable_image_paths)
        Feature.new do |feature|
          feature.name = record.name
          feature.metadata = record.metadata
          feature.feature_type = record.feature_type
          feature.geog = record.geog
          feature.importable_image_paths = importable_image_paths
          feature.make_valid = @make_valid
          feature.source_identifier = source_identifier
        end
      end
    end
  end

  # EXCEPTIONS

  class ImportError < StandardError; end
  class EmptyImportError < ImportError; end
end
