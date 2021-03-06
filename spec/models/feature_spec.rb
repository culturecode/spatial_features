require 'spec_helper'

describe Feature do
  new_dummy_class(:name => 'House')
  new_dummy_class(:name => 'Disaster')

  let(:house) { House.create }
  let(:disaster) { Disaster.create }

  describe '::intersecting' do
    before do
      create_polygon(Rectangle.new(1, 1), :spatial_model => house)
      create_polygon(Rectangle.new(1, 0.5), :spatial_model => disaster)
      create_polygon(Rectangle.new(1, 1, :x => 2), :spatial_model => House.create)
      create_polygon(Rectangle.new(1, 0.5, :x => 2), :spatial_model => Disaster.create)
    end

    it 'returns all feature columns' do
      expect(House.features.intersecting(disaster.features))
        .to all( have_attributes :attribute_names => Feature.column_names )
    end

    it 'includes the distance when :distance => true' do
      pending 'Test accidentally merged. Requires code from feature-spatial-calculation-optimization branch'
      expect(House.features.intersecting(disaster.features, :distance => true))
        .to all( have_attribute :distance_in_meters )
    end

    it 'returns the same records when :intersection_area => true' do
      pending 'Test accidentally merged. Requires code from feature-spatial-calculation-optimization branch'
      expect(House.features.intersecting(disaster.features, :intersection_area => true))
        .to match_array(House.features.intersecting(disaster.features))
    end

    it 'includes the intersection_area when :intersection_area => true' do
      pending 'Test accidentally merged. Requires code from feature-spatial-calculation-optimization branch'
      expect(House.features.intersecting(disaster.features, :intersection_area => true))
        .to all( have_attribute :intersection_area_in_square_meters )
    end
  end

  describe '::within_buffer' do
    before do
      create_polygon(Rectangle.new(1, 1), :spatial_model => house)
      create_polygon(Rectangle.new(1, 0.5), :spatial_model => disaster)
      create_polygon(Rectangle.new(1, 1, :x => 2), :spatial_model => House.create)
      create_polygon(Rectangle.new(1, 0.5, :x => 2), :spatial_model => Disaster.create)
    end

    shared_examples_for 'within_buffer' do |buffer, options|
      it 'includes the intersection_area when :intersection_area => true' do
        pending 'Test accidentally merged. Requires code from feature-spatial-calculation-optimization branch'
        expect(House.features.within_buffer(disaster.features, buffer, options.merge(:intersection_area => true)))
          .to all( have_attribute :intersection_area_in_square_meters )
      end

      it 'includes the distance when :distance => true' do
        pending 'Test accidentally merged. Requires code from feature-spatial-calculation-optimization branch'
        expect(House.features.within_buffer(disaster.features, buffer, options.merge(:distance => true)))
          .to all( have_attribute :distance_in_meters )
      end
    end

    context 'when buffer is 0' do
      it_behaves_like 'within_buffer', 0, {}
    end

    context 'when buffer is non 0' do
      it_behaves_like 'within_buffer', 1, {}
    end

    context 'when group => true' do
      it_behaves_like 'within_buffer', 0, {:group => true}
      it_behaves_like 'within_buffer', 1, {:group => true}
    end
  end

  describe '#cache_key' do
    it 'generates a cache_key with max and count' do
      House.create(:features => [create_polygon(Rectangle.new(1, 1))])
      expected = "#{Feature.maximum(:id)}-#{Feature.count}"
      expect(house.features.cache_key).to match(expected)
    end
  end

  describe '#features_cache_key' do
    it 'generates features_cache_key' do
      expect(house.features_cache_key).to be_a(String)
    end
  end

  describe 'has_spatial_features' do
    it 'evaluates model without error when no database table exists' do
      eval("class NoTable < ActiveRecord::Base; end")
      klass = NoTable

      klass.table_name = "some_table_that_does_not_exist"
      expect(klass.has_spatial_features).to be_truthy
    end
  end
end
