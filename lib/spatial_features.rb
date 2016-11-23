# Gems

require 'rgeo/shapefile'

# LIB
require 'spatial_features/caching'
require 'spatial_features/venn_polygons'
require 'spatial_features/controller_helpers/spatial_extensions'
require 'spatial_features/unzip'

require 'spatial_features/has_spatial_features'
require 'spatial_features/has_spatial_features/feature_import'
require 'spatial_features/has_spatial_features/delayed_feature_import'

require 'spatial_features/importers/base'
require 'spatial_features/importers/file'
require 'spatial_features/importers/kml'
require 'spatial_features/importers/kml_file'
require 'spatial_features/importers/geomark'
require 'spatial_features/importers/shapefile'

require 'spatial_features/workers/update_features_job'

require 'spatial_features/engine'

module SpatialFeatures
  module UncachedRelation
    include ActiveRecord::NullRelation
  end
end

# Load the act method
ActiveRecord::Base.send :extend, SpatialFeatures::ActMethod
