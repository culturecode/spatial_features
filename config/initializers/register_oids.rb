module PostGISTypes
  def initialize_type_map(mapping)
    super
    register_class_with_limit mapping, 'geometry', ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::OID::SpecializedString
    register_class_with_limit mapping, 'geography', ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::OID::SpecializedString
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do
  prepend PostGISTypes
end
