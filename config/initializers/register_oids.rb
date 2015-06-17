ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.tap do |klass|
  # Use identity which does no casting
  # klass::OID.register_type('geography', klass::OID::Identity.new)
  # klass::OID.register_type('geometry', klass::OID::Identity.new)
end
