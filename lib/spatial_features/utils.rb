module SpatialFeatures
  module Utils
    extend self

    def polymorphic_condition(scope, column_name)
      sql = "#{column_name}_type = ?"
      sql << " AND #{column_name}_id IN (#{id_sql(scope)})" unless scope.is_a?(Class)

      return class_of(scope).send :sanitize_sql, [sql, class_of(scope)]
    end

    # Returns the class for the given, class, scope, or record
    def class_of(object)
      case object
      when ActiveRecord::Base
        object.class
      when ActiveRecord::Relation
        object.klass
      else
        object
      end
    end

    def id_sql(object)
      if object.is_a?(ActiveRecord::Base)
        object.id || '0'
      else
        object.unscope(:select).select(:id).to_sql
      end
    end
  end
end
