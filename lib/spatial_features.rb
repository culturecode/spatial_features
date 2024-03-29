# Gems
require 'delayed_job_active_record'
require 'rgeo/shapefile'
require 'rgeo/geo_json'
require 'nokogiri'
require 'zip'

# LIB
require 'spatial_features/caching'
require 'spatial_features/uncached_result'
require 'spatial_features/venn_polygons'
require 'spatial_features/controller_helpers/spatial_extensions'
require 'spatial_features/download'
require 'spatial_features/unzip'
require 'spatial_features/utils'
require 'spatial_features/validation'

require 'spatial_features/has_spatial_features'
require 'spatial_features/has_spatial_features/queued_spatial_processing'
require 'spatial_features/has_spatial_features/feature_import'

require 'spatial_features/importers/base'
require 'spatial_features/importers/file'
require 'spatial_features/importers/geo_json'
require 'spatial_features/importers/esri_geo_json'
require 'spatial_features/importers/kml'
require 'spatial_features/importers/kml_file'
require 'spatial_features/importers/kml_file_arcgis'
require 'spatial_features/importers/geomark'
require 'spatial_features/importers/shapefile'

require 'spatial_features/engine'

# Load the act method
ActiveRecord::Base.send :extend, SpatialFeatures::ActMethod

# Suppress date warnings when unzipping KMZ saved by Google Earth, see https://github.com/rubyzip/rubyzip/issues/112
Zip.warn_invalid_date = false
