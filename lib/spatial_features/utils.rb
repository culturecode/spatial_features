module SpatialFeatures
  module Utils
    extend self

    def polymorphic_condition(scope, column_name)
      sql = "#{column_name}_type = ?"
      sql << " AND #{column_name}_id IN (#{id_sql(scope)})" unless scope.is_a?(Class)

      return class_of(scope).send :sanitize_sql, [sql, base_class_of(scope)]
    end

    def class_name_with_ancestors(object)
      class_of(object).ancestors.select {|k| k < ActiveRecord::Base }.map(&:to_s)
    end

    def base_class_of(object)
      base_class(class_of(object))
    end

    def base_class(klass)
      case klass
      when String
        klass.constantize.base_class.to_s
      when ActiveRecord::Base
        klass.class.base_class
      when Class
        klass.base_class
      end
    end

    # Returns the class for the given, class, scope, or record
    def class_of(object)
      case object
      when ActiveRecord::Base
        object.class
      when ActiveRecord::Relation
        object.klass
      when String
        object.constantize
      else
        object
      end
    end

    def id_sql(object)
      case object
      when ActiveRecord::Base
        object.id || '0'
      when String
        id_sql(object.constantize)
      else
        object.unscope(:select).select(:id).to_sql
      end
    end

    # Convert a hash of GeoJSON data into a PostGIS geometry object
    def geom_from_json(geometry)
      ActiveRecord::Base.connection.select_value("SELECT ST_GeomFromGeoJSON('#{geometry.to_json}')")
    end
  end
end
