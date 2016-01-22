ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do
  def initialize_type_map_with_postgres_oids mapping
    initialize_type_map_without_postgres_oids mapping
    register_class_with_limit mapping, 'geometry', ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::OID::SpecializedString
    register_class_with_limit mapping, 'geography', ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::OID::SpecializedString
  end

  alias_method_chain :initialize_type_map, :postgres_oids
end
