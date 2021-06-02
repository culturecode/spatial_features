def open_fixture_file(path)
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/#{path}")
end

def kml_file
  open_fixture_file("test.kml")
end

def kmz_file
  open_fixture_file("test.kmz")
end

def kmz_file_features_without_placemarks
  open_fixture_file("kmz_file_features_without_placemarks.kmz")
end

def kml_file_with_invalid_placemark
  open_fixture_file("kml_file_with_invalid_placemark.kml")
end

def shapefile
  open_fixture_file("shapefile.zip")
end

def shapefile_without_projection
  open_fixture_file("shapefile_without_projection.zip")
end

def shapefile_with_upcase_shp
  open_fixture_file("shapefile_with_upcase_shp.zip")
end

def shapefile_without_shape_format
  open_fixture_file("shapefile_without_shape_format.zip")
end

def shapefile_without_shape_index
  open_fixture_file("shapefile_without_shape_index.zip")
end

def shapefile_with_missing_dbf_file
  open_fixture_file("shapefile_with_missing_dbf_file.zip")
end

def shapefile_with_incorrect_shx_basename
  open_fixture_file("shapefile_with_incorrect_shx_basename.zip")
end

def archive_without_any_known_file
  open_fixture_file("archive_without_any_known_file.zip")
end
