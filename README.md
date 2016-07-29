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
      geom geometry(Geometry,3005),
      geom_lowres geometry(Geometry,3005),
      kml text,
      kml_lowres text,
      metadata hstore,
      area double precision,
      north numeric(9,6),
      east numeric(9,6),
      south numeric(9,6),
      west numeric(9,6)
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
