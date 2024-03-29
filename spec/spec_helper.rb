# Configure Rails Environment
require 'rails'
require 'active_record'
require 'spatial_features'
require 'pry-byebug'

Rails.logger = Logger.new(STDOUT)

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

# Load app files
Dir["#{File.dirname(__FILE__)}/../app/**/*.rb"].each { |f| require f }

ActiveRecord::Base.establish_connection(
  :adapter => "postgresql",
  :host => "localhost",
  :encoding => "unicode",
  :database => "spatial_features_test",
  :username => ENV["POSTGRES_USER"],
  :password => ENV["POSTGRES_PASSWORD"]
)
# Load OID initializer
Dir["#{File.dirname(__FILE__)}/../config/initializers/**/*.rb"].each { |f| require f }

NAME_COLUMN_LIMIT = 100

ActiveRecord::Schema.define(:version => 0) do
  enable_extension 'hstore'
  enable_extension 'postgis'

  create_table :features, :force => true do |t|
    t.references :spatial_model, :polymorphic => true, :index => false
    t.string :name, :limit => NAME_COLUMN_LIMIT
    t.hstore :metadata
    t.column :geog, :geography, :index => { :using => :gist }
    t.column :geom, 'geometry(Geometry,26910)', :index => { :using => :gist }
    t.column :geom_lowres, 'geometry(Geometry,26910)', :index => { :using => :gist }
    t.virtual :tilegeom, :type => 'geometry(Geometry,3857)', as: "ST_Transform(geom, 3857)", stored: true, :index => { :using => :gist }
    t.virtual :feature_type, :type => :string, as: "CASE GeometryType(geog) WHEN 'POLYGON' THEN 'polygon' WHEN 'MULTIPOLYGON' THEN 'polygon' WHEN 'GEOMETRYCOLLECTION' THEN 'polygon' WHEN 'LINESTRING' THEN 'line' WHEN 'MULTILINESTRING' THEN 'line' WHEN 'POINT' THEN 'point' WHEN 'MULTIPOINT' THEN 'point' END", stored: true, :index => true
    t.virtual :centroid, :type => :geography, as: "ST_PointOnSurface(geog::geometry)", stored: true
    t.virtual :area, :type => :decimal, as: "ST_Area(geog)", stored: true
    t.virtual :north, :type => :decimal, as: "ST_YMax(geog::geometry)", stored: true
    t.virtual :east, :type => :decimal, as: "ST_XMax(geog::geometry)", stored: true
    t.virtual :south, :type => :decimal, as: "ST_YMin(geog::geometry)", stored: true
    t.virtual :west, :type => :decimal, as: "ST_XMin(geog::geometry)", stored: true
    t.string :type, :index => true
    t.string :source_identifier, :index => true
  end

  add_index :features, :spatial_model_type
  add_index :features, [:spatial_model_id, :spatial_model_type]

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

  create_table :delayed_jobs, :force => true do |table|
    table.integer  :priority, :default => 0      # Allows some jobs to jump to the front of the queue
    table.integer  :attempts, :default => 0      # Provides for retries, but still fail eventually.
    table.text     :handler                      # YAML-encoded string of the object that will do work
    table.text     :last_error                   # reason for last failure (See Note below)
    table.datetime :run_at                       # When to run. Could be Time.zone.now for immediately, or sometime in the future.
    table.datetime :locked_at                    # Set when a client is working on this object
    table.datetime :failed_at                    # Set when all retries have failed (actually, by default, the record is deleted instead)
    table.string   :locked_by                    # Who is working on this object (if locked)
    table.string   :queue                        # The name of the queue this job is in
    table.timestamps
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

  config.color = true
end

# Make it easy to say expect(object).to not_have_any( be_sunday )
# The opposite of saying expect(object).to all( be_sunday )
RSpec::Matchers.define_negated_matcher :have_none, :include
