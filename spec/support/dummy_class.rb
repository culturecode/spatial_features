# DUMMY
# A class used to create searchable subclasses
$DUMMY_CLASS_COUNTER = 0
class CreateDummyTable < ActiveRecord::Migration[4.2]
  def self.make_table(table_name = 'dummies', column_names = [])
    create_table table_name, :force => true do |t|
      column_names.each do |name, type = :string|
        t.column name, type
      end
      t.column :features_hash, :string
      t.column :features_area, :decimal
    end
  end
end

def new_dummy_class(*column_names, name: "Dummy#{$DUMMY_CLASS_COUNTER}", parent: ActiveRecord::Base, **columns_with_types, &block)
  $DUMMY_CLASS_COUNTER += 1

  # Create the class
  klass = Class.new(parent)

  # Name the class
  Object.send(:remove_const, name) if Object.const_defined?(name)
  Object.const_set(name, klass)

  if parent == ActiveRecord::Base
    # Create the table
    klass.table_name = "dummies_#{$DUMMY_CLASS_COUNTER}"
    CreateDummyTable.make_table(klass.table_name, column_names.flatten + columns_with_types.to_a)
  end

  # Init the class
  klass.has_spatial_features
  klass.class_eval(&block) if block_given?

  return klass
end
