# Configure Rails Environment
require 'rails'
require 'active_record'
require 'spatial_features'

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

ActiveRecord::Base.establish_connection(:adapter => "postgresql", :database => "spatial_features_test")

# Load OID initializer
Dir["#{File.dirname(__FILE__)}/../config/initializers/**/*.rb"].each { |f| require f }

ActiveRecord::Schema.define(:version => 0) do
  execute("
    CREATE EXTENSION IF NOT EXISTS hstore SCHEMA public;
    CREATE EXTENSION IF NOT EXISTS postgis SCHEMA public;
  ")

  create_table :features, :force => true do |t|
    t.references :spatial_model, :polymorphic => true, :index => true
    t.string :name
    t.string :feature_type
    t.hstore :metadata
    t.decimal :area
    t.column :geog, :geography
    t.column :geog_lowres, 'geography(Geometry,4326)'
    t.column :geom, 'geometry(Geometry,26910)'
    t.text :kml
    t.text :kml_lowres
  end

  create_table :spatial_caches, :force => true do |t|
    t.references :spatial_model, :polymorphic => true, :index => true
    t.string :intersection_model_type
    t.decimal :intersection_cache_distance
    t.string :features_hash
    t.timestamps :null => false
  end

  create_table :spatial_proximities, :force => true do |t|
    t.references :model_a, :polymorphic => true, :index => true
    t.references :model_b, :polymorphic => true, :index => true
    t.decimal :distance_in_meters
    t.decimal :intersection_area_in_square_meters
  end
end


# Manually implement transactional examples because we're not using rspec_rails
RSpec.configure do |config|
  config.around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end

# Make it easy to say expect(object).to not_have_any( be_sunday )
# The opposite of saying expect(object).to all( be_sunday )
RSpec::Matchers.define_negated_matcher :have_none, :include
