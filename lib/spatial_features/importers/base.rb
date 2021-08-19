require 'digest/md5'

module SpatialFeatures
  module Importers
    class Base
      attr_reader :errors

      def initialize(data, make_valid: false)
        @make_valid = make_valid
        @data = data
        @errors = []
      end

      def features
        @features ||= build_features
      end

      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(@data)
      end

      # factory method that should always be used when creating importers
      # returns an array of Importer::* objects
      def self.create(data, **options)
        new(data, **options)
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
        Feature.new(:name => record.name, :metadata => record.metadata, :feature_type => record.feature_type, :geog => record.geog, :make_valid => @make_valid)
      end
    end
  end

  # EXCEPTIONS

  class ImportError < StandardError; end
end
