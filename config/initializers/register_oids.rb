module PostGISTypes
  def initialize_type_map(m = type_map)
    super
    %w[
      geography
      geometry
    ].each do |geo_type|
      m.register_type geo_type, ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::OID::SpecializedString.new(geo_type.to_sym)
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do
  prepend PostGISTypes
end
