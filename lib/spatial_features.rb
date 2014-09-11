# LIB
require 'spatial_features/caching'
require 'spatial_features/venn_polygons'
require 'spatial_features/has_spatial_features'

require 'spatial_features/import/arcgis_kmz_features'

require 'spatial_features/controller_helpers/spatial_extensions'

require 'spatial_features/models/feature'
require 'spatial_features/models/spatial_cache'
require 'spatial_features/models/spatial_proximity'

require 'spatial_features/engine'

module SpatialFeatures
end

# Load the act method
ActiveRecord::Base.send :extend, SpatialFeatures::ActMethod
