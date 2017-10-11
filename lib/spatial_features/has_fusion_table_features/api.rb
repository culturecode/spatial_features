module SpatialFeatures
  module FusionTables
    module API
      extend self

      FEATURE_COLUMNS = {
        :name => 'STRING',
        :spatial_model_type => 'STRING',
        :spatial_model_id => 'NUMBER',
        :kml_lowres => 'LOCATION',
        :colour => 'STRING',
        :metadata => 'STRING'
      }
      TABLE_STYLE = {
        :polygon_options => { :fill_color_styler => { :kind => 'fusiontables#fromColumn', :column_name => 'colour' },
                              :stroke_color_styler => { :kind => 'fusiontables#fromColumn', :column_name => 'colour' },
                              :stroke_weight => 1
                            },
        :polyline_options => { :stroke_color_styler => { :kind => 'fusiontables#fromColumn', :column_name => 'colour'} }
      }

      TABLE_TEMPLATE = {
        :body => "<h3>{name}</h3>{metadata}"
      }

      def find_or_create_table(name)
        find_table(name) || create_table(name)
      end

      def create_table(name)
        table_id = service.create_table(name, FEATURE_COLUMNS.collect {|name, type| {:name => name, :type => type} })
        service.share_table(table_id)
        service.insert_style(table_id, TABLE_STYLE)
        service.insert_template(table_id, TABLE_TEMPLATE)
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
        service.replace_rows(table_id, features_to_csv(features, colour))
      end

      def set_style(table_id, style)
        service.style_ids(table_id).each do |style_id|
          service.delete_style(table_id, style_id)
        end
        service.insert_style(table_id, style)
      end

      def service
        @service ||= Service.new(Configuration.service_account_credentials)
      end

      private

      def features_to_csv(features, colour)
        ActiveRecord::Associations::Preloader.new.preload(features, :spatial_model) if colour.is_a?(Symbol)

        csv = CSV.generate do |csv|
          features.each do |feature|
            csv << FEATURE_COLUMNS.keys.collect do |attribute|
              case attribute
              when :colour
                render_feature_colour(feature, colour)
              when :metadata
                render_feature_metadata(feature)
              else
                feature.send(attribute)
              end
            end
          end
        end

        file = Tempfile.new('features')
        file.write(csv)
        return file
      end

      def render_feature_metadata(feature)
        feature.metadata.collect do |name, val|
          "<b>#{name}:</b> #{val}"
        end.join('<br/>')
      end

      def render_feature_colour(feature, colour)
        case colour
        when Symbol
          feature.spatial_model.send(colour)
        when Proc
          colour.call(feature)
        else
          colour
        end.paint.to_ft_hex

      rescue Chroma::Errors::UnrecognizedColor
        nil
      end
    end
  end
end
