require 'digest/md5'

module SpatialFeatures
  module Importers
    class Base
      attr_reader :errors

      def initialize(data, skip_invalid: false, make_valid: false)
        @make_valid = make_valid
        @feature_error_messages = []
        @data = data
        @errors = []
      end

      def features
        @features ||= build_features
      end

      def cache_key
        @cache_key ||= Digest::MD5.hexdigest(@data)
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
        @data.each(&block)
      end

      def build_feature(record)
        Feature.new(:name => record.name, :metadata => record.metadata, :feature_type => record.feature_type, :geog => record.geog, :make_valid => @make_valid)
      end
    end
  end
end