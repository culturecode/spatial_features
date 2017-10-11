module SpatialFeatures
  module FusionTables
    class Service
      APPLICATION_NAME = 'Fusion Tables + Spatial Features'
      GOOGLE_AUTH_SCOPES = %w(https://www.googleapis.com/auth/fusiontables https://www.googleapis.com/auth/drive)

      def initialize(service_account_credentials_path)
        @authorization = get_authorization(service_account_credentials_path, GOOGLE_AUTH_SCOPES)
      end

      def table_ids
        tables.collect(&:table_id)
      end

      def tables
        fusion_tables_service.list_tables(max_results: 10000).items || []
      end

      def create_table(name, columns = [], table_options = {})
        table_object = {:name => name, :columns => columns, :is_exportable => true}.merge(table_options)
        fusion_tables_service.insert_table(table_object, :fields => 'table_id').table_id
      end

      def delete_table(table_id)
        fusion_tables_service.delete_table(table_id)
      end

      def style_ids(table_id)
        styles(table_id).collect(&:style_id)
      end

      def styles(table_id)
        fusion_tables_service.list_styles(table_id).items
      end

      def delete_style(table_id, style_id)
        fusion_tables_service.delete_style(table_id, style_id, :fields => nil)
      end

      def insert_style(table_id, style)
        style.reverse_merge! 'name' => 'default_table_style', 'isDefaultForTable' => true
        fusion_tables_service.insert_style(table_id, style, :fields => 'styleId')
      end

      def delete_template(table_id, template_id)
        fusion_tables_service.delete_template(table_id, template_id, :fields => nil)
      end

      def insert_template(table_id, template)
        template.reverse_merge! 'name' => 'default_table_template'
        fusion_tables_service.insert_template(table_id, template, :fields => 'templateId')
      end

      def delete_row(table_id, row_id)
        fusion_tables_service.sql_query("DELETE FROM #{table_id} WHERE ROWID = #{row_id}")
      end

      def row_ids(table_id, conditions = {})
        clause = conditions.collect {|column, value| ActiveRecord::Base.send(:sanitize_sql_array, ["? IN (?)", column, value]) }.join(' AND ')
        where = "WHERE #{clause}" if clause.present?
        return fusion_tables_service.sql_query_get("SELECT rowid FROM #{table_id} #{where}}").rows.flatten
      end

      # Process mutliple commands in a single HTTP request
      def bulk(&block)
        fusion_tables_service.batch do
          block.call(self)
        end
      end

      def replace_rows(table_id, csv)
        fusion_tables_service.replace_table_rows(table_id, :upload_source => csv, :options => {:open_timeout_sec => 1.hour})
      end

      def upload_rows(table_id, csv)
        fusion_tables_service.import_rows(table_id, :upload_source => csv, :options => {:open_timeout_sec => 1.hour})
      end

      def share_table(table_id)
        permission = {:type => 'anyone', :role => 'reader', :withLink => true}
        drive_service.create_permission(table_id, permission, :fields => 'id')
      end

      def fusion_tables_service
        @fusion_tables_service ||= Google::Apis::FusiontablesV2::FusiontablesService.new.tap do |service|
          service.client_options.application_name = APPLICATION_NAME
          service.authorization = @authorization
        end
      end

      def drive_service
        @drive_service ||= Google::Apis::DriveV3::DriveService.new.tap do |drive|
          drive.client_options.application_name = APPLICATION_NAME
          drive.authorization = @authorization
        end
      end

      def get_authorization(service_account_credentials_path, scopes)
        ENV['GOOGLE_APPLICATION_CREDENTIALS'] = service_account_credentials_path
        return Google::Auth.get_application_default(scopes)
      end
    end
  end
end
