# DUMMY
# A class used to create searchable subclasses
$DUMMY_CLASS_COUNTER = 0
class CreateDummyTable < ActiveRecord::Migration
  def self.make_table(table_name = 'dummies', column_names = [])
    create_table table_name, :force => true do |t|
      column_names.each do |name|
        t.column name, :string
      end
    end
  end
end

def new_dummy_class(*column_names, &block)
  $DUMMY_CLASS_COUNTER += 1
  klass_name = "Dummy#{$DUMMY_CLASS_COUNTER}"

  # Create the class
  eval("class #{klass_name} < ActiveRecord::Base; end")
  klass = klass_name.constantize

  klass.table_name = "dummies_#{$DUMMY_CLASS_COUNTER}"
  CreateDummyTable.make_table(klass.table_name, column_names.flatten)

  klass.has_spatial_features

  # If the class is Dummy1 this returns :dummy1
  klass.class_eval do
    def self.association_name
      self.name.underscore.to_sym
    end
  end

  # Eval anything inside the dummy class
  if block_given?
    klass.instance_eval(&block)
  end

  return klass
end
