# Spatial Features

Adds spatial methods to a model.

## Migration
```ruby
execute("
  CREATE TABLE features (
      id integer NOT NULL,
      spatial_model_type character varying(255),
      spatial_model_id integer,
      name character varying(255),
      feature_type character varying(255),
      geog geography,
      kml text,
      geog_lowres geography(Geometry,4326),
      geom geometry(Geometry,26910),
      metadata hstore,
      kml_lowres text,
      area double precision
  );

  CREATE TABLE spatial_caches (
      id integer NOT NULL,
      intersection_model_type character varying(255),
      spatial_model_type character varying(255),
      spatial_model_id integer,
      created_at timestamp without time zone,
      updated_at timestamp without time zone,
      intersection_cache_distance double precision
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
