# Spatial Features

Adds spatial methods to a model.

## Installation

1. Install libraries
  - PostGIS
  - libgeos and gdal (optional libraries required for Shapefile import)

    ```bash
    # Ubuntu Installation instructions. Source: https://github.com/rgeo/rgeo/issues/26#issuecomment-106059741
    sudo apt-get -y install libgeos-3.4.2 libgeos-dev libproj0 libproj-dev gdal-bin
    sudo ln -s /usr/lib/libgeos-3.4.2.so /usr/lib/libgeos.so
    sudo ln -s /usr/lib/libgeos-3.4.2.so /usr/lib/libgeos.so.1
    ```

2. Create spatial tables

  ```ruby
  execute("
    CREATE EXTENSION hstore;
    CREATE EXTENSION postgis;

    CREATE TABLE features (
        id integer NOT NULL,
        type character varying(255),
        spatial_model_type character varying(255),
        spatial_model_id integer,
        name character varying(255),
        feature_type character varying(255),
        geog geography,
        geom geometry(Geometry,4326),
        geom_lowres geometry(Geometry,4326),
        tilegeom geometry(Geometry,3857),
        metadata hstore,
        area double precision,
        north numeric(9,6),
        east numeric(9,6),
        south numeric(9,6),
        west numeric(9,6),
        centroid geography,
    );

    CREATE SEQUENCE features_id_seq START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
    ALTER SEQUENCE features_id_seq OWNED BY features.id;
    ALTER TABLE ONLY features ALTER COLUMN id SET DEFAULT nextval('features_id_seq'::regclass);
    ALTER TABLE ONLY features ADD CONSTRAINT features_pkey PRIMARY KEY (id);

    CREATE INDEX index_features_on_feature_type ON features USING btree (feature_type);
    CREATE INDEX index_features_on_spatial_model_id_and_spatial_model_type ON features USING btree (spatial_model_id, spatial_model_type);
    CREATE INDEX index_features_on_geom ON features USING gist (geom);
    CREATE INDEX index_features_on_geom_lowres ON features USING gist (geom_lowres);
    CREATE INDEX index_features_on_tilegeom ON features USING gist (tilegeom);

    CREATE TABLE spatial_caches (
        id integer NOT NULL,
        intersection_model_type character varying(255),
        spatial_model_type character varying(255),
        spatial_model_id integer,
        created_at timestamp without time zone,
        updated_at timestamp without time zone,
        intersection_cache_distance double precision,
        features_hash character varying(255)
    );

    CREATE SEQUENCE spatial_caches_id_seq START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
    ALTER SEQUENCE spatial_caches_id_seq OWNED BY spatial_caches.id;
    ALTER TABLE ONLY spatial_caches ALTER COLUMN id SET DEFAULT nextval('spatial_caches_id_seq'::regclass);
    ALTER TABLE ONLY spatial_caches ADD CONSTRAINT spatial_caches_pkey PRIMARY KEY (id);

    CREATE INDEX index_spatial_caches_on_spatial_model ON spatial_caches USING btree (spatial_model_id, spatial_model_type);

    CREATE TABLE spatial_proximities (
        id integer NOT NULL,
        model_a_type character varying(255),
        model_a_id integer,
        model_b_type character varying(255),
        model_b_id integer,
        distance_in_meters double precision,
        intersection_area_in_square_meters double precision
    );

    CREATE SEQUENCE spatial_proximities_id_seq START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
    ALTER SEQUENCE spatial_proximities_id_seq OWNED BY spatial_proximities.id;
    ALTER TABLE ONLY spatial_proximities ALTER COLUMN id SET DEFAULT nextval('spatial_proximities_id_seq'::regclass);
    ALTER TABLE ONLY spatial_proximities ADD CONSTRAINT spatial_proximities_pkey PRIMARY KEY (id);

    CREATE INDEX index_spatial_proximities_on_model_a ON spatial_proximities USING btree (model_a_id, model_a_type);
    CREATE INDEX index_spatial_proximities_on_model_b ON spatial_proximities USING btree (model_b_id, model_b_type);
  ")
  ```

## Usage

In your model

```ruby
class Location < ActiveRecord::Base
  has_spatial_features
end

Person.new(:features => [Feature.new(:geog => 'some binary PostGIS Geography string')])
```

### Import

You can specify multiple import sources for geometry. Each key is a method that returns the data for the Importer, and
each value is the Importer to use to parse the data. Options can be passed in place of the Importer name, but must still
include a `name` key with the name of the importer. See each Importer for more details.
```ruby
def ImageImporter
  def self.call(feature, image_paths)
    image_paths.each do |pathname|
      # ...
    end
  end
end

class Location < ActiveRecord::Base
  has_spatial_features :image_handlers => ['ImageImporter'],
                       :import => {
                         :remote_kml_url => { :name => 'KMLFile', :feature_name => lambda {|source_feature| source_feature.metadata['shapeID'] },
                         :file => 'File', :geojson => 'ESRIGeoJSON' }
                       }

  def remote_kml_url
    "www.test.com/kml/#{id}.kml"
  end

  def file
    File.open('local/files/my_kml')
  end

  def geojson
    { "type" => "FeatureCollection", "features" => [] }
  end
end
```

### SpatialFeatures::Importers::Shapefile

#### Default Options

Default options can be specified on the Shapefile importer class itself.

- ##### default_proj4_projection
  A proj4 formatted projection string to use when no other projection has been specified either in the shapefile or the
  importer instance.

  Example:
  ```ruby
    SpatialFeatures::Importers::Shapefile.default_proj4_projection = "+proj=aea +lat_1=50 +lat_2=58.5 +lat_0=45 +lon_0=-126 +x_0=1000000 +y_0=0 +ellps=GRS80 +datum=NAD83 +units=m +no_defs"
  ```

  Default: `nil`

## Upgrading From 2.7.x to 2.8.0
Features now generate an `AggregateFeature` comprised of a union of all their spatial model's features. This improves query performance because
unioning is precalculated in these shapes instead of at query time.

```ruby
# In your migration
add_column :features, :type, :string
Feature.reset_column_information
AbstractFeature.update_all(:type => 'Feature')
Feature.refresh_aggregates
```

## Upgrading From 2.8.x to 3.0
Cached KML layers are no longer generated as Mapbox Vector Tile is the primary expected output. The columns can be left
in place or you can remove the KML cache columns.

```ruby
remove_column :features, :kml
remove_column :features, :kml_lowres
remove_column :features, :kml_centroid
```

A new `tilegeom` column has been added to support MVT tile output, which is now the preferred map output format instead
of GeoJSON or KML. It keeps memory usage low and is fast to generate.

```ruby
add_column :features, :tilegeom, :geometry
add_index :features, :tilegeom, :using => :gist
Feature.update_all('tilegeom = ST_Transform(geom, 3857)')
```

## Upgrading From 3.0/3.1 to 3.2
SpatialProximity now expects the `model_a` and `model_b` records to be decided based on the name of the record type so
queries can be optimized. Migrate existing SpatialProximity rows to this new scheme by running the code below.

```ruby
SpatialProximity.normalize
```

## Upgrading From 3.2/3.3 to 3.4
Features now record the source they were imported from in the new `source_identifier` column. This column is indexed and
can be used filter features by source.

```ruby
add_column :features, :source_identifier, :string
add_index :features, :source_identifier
MyModel.update_features!(:force => true) # Force an `update_features!` will populate the source_identifier column.
```

## Upgrading From 3.4 to 3.5
The gem now relies on virtual columns to set a number of derived column values.
```ruby
  change_table :features do |t|
    t.remove :tilegeom, :feature_type, :centroid, :area, :north, :east, :south, :west

    t.virtual :tilegeom, :type => 'geometry(Geometry,3857)', as: "ST_Transform(geom, 3857)", stored: true, :index => { :using => :gist }
    t.virtual :feature_type, :type => :string, as: "CASE GeometryType(geog) WHEN 'POLYGON' THEN 'polygon' WHEN 'MULTIPOLYGON' THEN 'polygon' WHEN 'GEOMETRYCOLLECTION' THEN 'polygon' WHEN 'LINESTRING' THEN 'line' WHEN 'MULTILINESTRING' THEN 'line' WHEN 'POINT' THEN 'point' WHEN 'MULTIPOINT' THEN 'point' END", stored: true, :index => true
    t.virtual :centroid, :type => :geography, as: "ST_PointOnSurface(geog::geometry)", stored: true
    t.virtual :area, :type => :decimal, as: "ST_Area(geog)", stored: true
    t.virtual :north, :type => :decimal, as: "ST_YMax(geog::geometry)", stored: true
    t.virtual :east, :type => :decimal, as: "ST_XMax(geog::geometry)", stored: true
    t.virtual :south, :type => :decimal, as: "ST_YMin(geog::geometry)", stored: true
    t.virtual :west, :type => :decimal, as: "ST_XMin(geog::geometry)", stored: true
  end
```

## Testing

Create a postgres database:
```bash
createdb spatial_features_test
```

There are multiple gemfiles available for testing against different Rails versions.  Set `BUNDLE_GEMFILE` to target them, e.g.

```bash
bundle install
BUNDLE_GEMFILE=gemfiles/rails_7_0.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7_0.gemfile bundle exec rspec
```
