# Gems
require 'rgeo/shapefile'
require 'nokogiri'
require 'zip'
require 'googleauth'
require 'google/apis/fusiontables_v2'
require 'google/apis/drive_v3'

# LIB
require 'spatial_features/caching'
require 'spatial_features/venn_polygons'
require 'spatial_features/controller_helpers/spatial_extensions'
require 'spatial_features/download'
require 'spatial_features/unzip'

require 'spatial_features/has_spatial_features'
require 'spatial_features/has_spatial_features/feature_import'
require 'spatial_features/has_spatial_features/delayed_feature_import'

require 'spatial_features/has_fusion_table_features'
require 'spatial_features/has_fusion_table_features/api'
require 'spatial_features/has_fusion_table_features/configuration'
require 'spatial_features/has_fusion_table_features/service'

require 'spatial_features/importers/base'
require 'spatial_features/importers/file'
require 'spatial_features/importers/kml'
require 'spatial_features/importers/kml_file'
require 'spatial_features/importers/kml_file_arcgis'
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
ActiveRecord::Base.send :extend, SpatialFeatures::FusionTables::ActMethod

# Suppress date warnings when unzipping KMZ saved by Google Earth, see https://github.com/rubyzip/rubyzip/issues/112
Zip.warn_invalid_date = false
