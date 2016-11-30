module SpatialFeatures
  module FusionTables
    module ActMethod
      def has_fusion_table_features(options = {})
        class_attribute :fusion_table_features_options
        self.fusion_table_features_options = options

        include InstanceMethods
        extend ClassMethods
      end
    end

    module ClassMethods
      def to_fusion_condition
        sanitize_sql(["spatial_model_id IN (?)", pluck(:id)])
      end

      def update_fusion_tables(group_options = {})
        fusion_table_groups(group_options) do |fusion_table_id, records, group_features|
          API.set_features(fusion_table_id, group_features, :colour => fusion_table_features_options[:colour])
        end
      end

      def delete_fusion_tables(group_options = {})
        fusion_table_groups(group_options) do |fusion_table_id, records, group_features|
          API.delete_table(fusion_table_id)
        end
        @fusion_table_id_cache = nil
      end

      def acts_like_fusion_table_features?
        true
      end

      def fusion_table_id_cache
        @fusion_table_id_cache ||= Hash.new {|hash, table_name| hash[table_name] = API.find_or_create_table(table_name) }
          .replace(API.tables.collect {|table| [table.name, table.table_id] }.to_h) # Warm the cache
      end

      private

      def fusion_table_groups(only: [], except: [])
        groups = all.group_by(&:fusion_table_id)
        groups.select! {|fusion_table_id| Array.wrap(only).include?(fusion_table_id) } if only.present?
        groups.select! {|fusion_table_id| !Array.wrap(except).include?(fusion_table_id) } if except.present?
        groups.each do |fusion_table_id, records|
          yield fusion_table_id, records, features.where(:spatial_model_id => records)
        end
      end
    end

    module InstanceMethods
      def acts_like_fusion_table_features?
        true
      end

      def update_fusion_table
        self.class.update_fusion_tables(only: fusion_table_id)
      end

      def delete_fusion_table
        self.class.delete_fusion_tables(only: fusion_table_id)
      end

      def fusion_table_id
        self.class.fusion_table_id_cache[fusion_table_name]
      end

      def fusion_table_name
        case fusion_table_features_options[:table_name]
        when Symbol
          send(fusion_table_features_options[:table_name])
        when String
          fusion_table_features_options[:table_name]
        else
          self.class.table_name
        end
      end

      def to_fusion_condition
        self.class.where(:id => self).to_fusion_condition
      end
    end
  end
end
