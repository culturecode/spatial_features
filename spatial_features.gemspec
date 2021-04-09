$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "spatial_features/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "spatial_features"
  s.version     = SpatialFeatures::VERSION
  s.authors     = ["Ryan Wallace", "Nicholas Jakobsen"]
  s.email       = ["contact@culturecode.ca"]
  s.homepage    = "https://github.com/culturecode/spatial_features"
  s.summary     = "Adds spatial methods to a model."
  s.description = "Adds spatial methods to a model."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  s.test_files = Dir["test/**/*"]

  s.add_runtime_dependency "rails", '>= 4.2', '< 6.0'
  s.add_runtime_dependency "delayed_job_active_record", '~> 4.1'
  s.add_runtime_dependency "rgeo-shapefile", '~> 3.0'
  s.add_runtime_dependency "rubyzip", '>= 1.0.0'
  s.add_runtime_dependency "nokogiri", '~> 1.6'
  s.add_runtime_dependency "chroma", "~> 0.1.0"

  s.add_development_dependency "pg", '~> 0'
  s.add_development_dependency "rspec", '~> 3.5'
end
