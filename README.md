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
    CREATE TABLE features (
        id integer NOT NULL,
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

    CREATE TABLE spatial_proximities (
        id integer NOT NULL,
        model_a_type character varying(255),
        model_a_id integer,
        model_b_type character varying(255),
        model_b_id integer,
        distance_in_meters double precision,
        intersection_area_in_square_meters double precision
    );
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
