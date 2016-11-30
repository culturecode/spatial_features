module SpatialFeatures
  module FusionTables
    module API
      extend self

      FEATURE_COLUMNS = {:name => 'STRING', :spatial_model_type => 'STRING', :spatial_model_id => 'NUMBER', :kml_lowres => 'LOCATION', :colour => 'STRING'}
      TABLE_STYLE = {
        :polygon_options => { :fill_color_styler => { :kind => 'fusiontables#fromColumn', :column_name => 'colour' }, :stroke_color => '#000000', :stroke_opacity => 0.2 },
        :polyline_options => { :stroke_color_styler => { :kind => 'fusiontables#fromColumn', :column_name => 'colour'} }
      }

      def find_or_create_table(name)
        find_table(name) || create_table(name)
      end

      def create_table(name)
        table_id = service.create_table(name, FEATURE_COLUMNS.collect {|name, type| {:name => name, :type => type} })
        service.share_table(table_id)
        service.insert_style(table_id, TABLE_STYLE)
        return table_id
      end

      def find_table(name)
        service.tables.find {|table| table.name == name }.try(:table_id)
      end

      def delete_table(table_id)
        service.delete_table(table_id)
      end

      def tables
        service.tables
      end

      def set_features(table_id, features, colour: nil)
        colour_features(features, colour)
        service.replace_rows(table_id, features_to_csv(features))
      end

      def service
        @service ||= Service.new(Configuration.service_account_credentials)
      end

      private

      def features_to_csv(features)
        csv = CSV.generate do |csv|
          features.each do |feature|
            csv << FEATURE_COLUMNS.keys.collect {|attribute| feature.send(attribute) }
          end
        end

        file = Tempfile.new('features')
        file.write(csv)
        return file
      end

      def colour_features(features, colour)
        case colour
        when Symbol
          ActiveRecord::Associations::Preloader.new.preload(features, :spatial_model)
          features.each do |feature|
            feature.define_singleton_method(:colour) do
              spatial_model.send(colour)
            end
          end
        when Proc
          features.each do |feature|
            feature.define_singleton_method(:colour) do
              colour.call(feature)
            end
          end
        else
          features.each do |feature|
            feature.define_singleton_method(:colour) do
              colour
            end
          end
        end
      end
    end
  end
end
