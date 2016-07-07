# LIB
require 'spatial_features/caching'
require 'spatial_features/venn_polygons'
require 'spatial_features/has_spatial_features'

require 'spatial_features/import/arcgis_kmz_features'

require 'spatial_features/controller_helpers/spatial_extensions'

require 'spatial_features/workers/arcgis_update_features_job'

require 'spatial_features/engine'

module SpatialFeatures
  module UncachedRelation
    include ActiveRecord::NullRelation
  end
end

# Load the act method
ActiveRecord::Base.send :extend, SpatialFeatures::ActMethod
