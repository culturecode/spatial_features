def kml_file
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/test.kml")
end

def kmz_file
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/test.kmz")
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
