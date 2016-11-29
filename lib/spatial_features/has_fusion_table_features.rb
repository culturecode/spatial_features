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

      def init_fusion_table
        delete_fusion_table
        update_fusion_table
      end

      def update_fusion_table
        API.set_features(fusion_table_id, features, :colour => fusion_table_features_options[:colour])
      end

      def delete_fusion_table
        API.delete_table(fusion_table_id)
        @fusion_table_id = nil
      end

      def fusion_table_id
        @fusion_table_id ||= API.find_or_create_table(table_name)
      end

      def acts_like_fusion_table_features?
        true
      end
    end

    module InstanceMethods
      def acts_like_fusion_table_features?
        true
      end

      def fusion_table_id
        self.class.fusion_table_id
      end

      def to_fusion_condition
        self.class.where(:id => self).to_fusion_condition
      end
    end
  end
end
