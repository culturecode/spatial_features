require 'spec_helper'

describe SpatialFeatures do

  describe 'caching' do
    it 'is equivalent to cache all records using cache_record_proximity or cache_proximity'
  end

  describe '::with_stale_spatial_cache' do
    it 'returns records whose features have been updated without updating the corresponding spatial cache'
  end

  describe '::without_spatial_cache' do
    it 'forms valid sql when the spatial model class has a column called spatial_model_type'
  end
end
