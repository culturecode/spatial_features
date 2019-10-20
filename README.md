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
        geom geometry(Geometry,3005),
        geom_lowres geometry(Geometry,3005),
        kml text,
        kml_lowres text,
        metadata hstore,
        area double precision,
        north numeric(9,6),
        east numeric(9,6),
        south numeric(9,6),
        west numeric(9,6),
        centroid geography,
        kml_centroid text
    );

    CREATE SEQUENCE features_id_seq START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
    ALTER SEQUENCE features_id_seq OWNED BY features.id;
    ALTER TABLE ONLY features ALTER COLUMN id SET DEFAULT nextval('features_id_seq'::regclass);
    ALTER TABLE ONLY features ADD CONSTRAINT features_pkey PRIMARY KEY (id);

    CREATE INDEX index_features_on_feature_type ON features USING btree (feature_type);
    CREATE INDEX index_features_on_spatial_model_id_and_spatial_model_type ON features USING btree (spatial_model_id, spatial_model_type);
    CREATE INDEX index_features_on_geom ON features USING gist (geom);
    CREATE INDEX index_features_on_geom_lowres ON features USING gist (geom_lowres);

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
each value is the Importer to use to parse the data. See each Importer for more details.
```ruby
class Location < ActiveRecord::Base
  has_spatial_features :import => { :remote_kml_url => 'KMLFile', :file => 'File' }

  def remote_kml_url
    "www.test.com/kml/#{id}.kml"
  end

  def file
    File.open('local/files/my_kml')
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
