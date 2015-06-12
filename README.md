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
      geog_lowres geography(Geometry,4326),
      geom geometry(Geometry,26910),
      kml text,
      kml_lowres text,
      metadata hstore
  );
")
```
