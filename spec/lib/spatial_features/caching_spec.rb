require 'spec_helper'

describe SpatialFeatures do

  describe 'caching' do
    it 'is equivalent to cache all records using cache_record_proximity or cache_proximity'
  end

  describe '::with_stale_spatial_cache' do
    it 'returns records whose features have been updated without updating the corresponding spatial cache'
  end
end
