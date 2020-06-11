def kml_file
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/test.kml")
end

def kmz_file
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/test.kmz")
end

def kmz_file_features_without_placemarks
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/kmz_file_features_without_placemarks.kmz")
end

def shapefile
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/shapefile.zip")
end

def shapefile_without_projection
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/shapefile_without_projection.zip")
end

def shapefile_with_upcase_shp
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/shapefile_with_upcase_shp.zip")
end

def shapefile_with_missing_required_file
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/shapefile_with_missing_required_file.zip")
end

def archive_without_any_known_file
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/archive_without_any_known_file.zip")
end
