def kml_file
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/test.kml")
end

def kmz_file
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/test.kmz")
end

def shapefile
  File.open("#{SpatialFeatures::Engine.root}/spec/fixtures/shapefile.zip")
end
