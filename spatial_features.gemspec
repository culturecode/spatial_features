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

  s.add_dependency "rails", '>= 4.2', '< 6.0'
  s.add_dependency "delayed_job_active_record", '~> 4.1'
  s.add_dependency "rgeo-shapefile", '~> 0.4'
  s.add_dependency "rubyzip", '~> 1.1'
  s.add_dependency "nokogiri", '~> 1.6'
  s.add_dependency "googleauth", '~> 0.5.1'
  s.add_dependency "google-api-client", '~> 0.9'
  s.add_dependency "chroma", "~> 0.1.0"

  s.add_development_dependency "pg", '~> 0'
  s.add_development_dependency "rspec", '~> 3.5'
end
