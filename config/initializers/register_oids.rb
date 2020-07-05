module PostGISTypes
  def initialize_type_map(m = type_map)
    super
    register_class_with_limit m, 'geometry', ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::OID::SpecializedString
    register_class_with_limit m, 'geography', ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::OID::SpecializedString
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do
  prepend PostGISTypes
end
