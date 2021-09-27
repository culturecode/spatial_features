require 'spec_helper'

describe SpatialFeatures::Importers::GeoJSON do
  subject { SpatialFeatures::Importers::GeoJSON.new(data) }

  context 'when given a string of GeoJSON' do
    let(:data) { JSON.parse(geojson_file.read) }

    describe '#features' do
      it 'returns all records' do
        expect(subject.features.count).to eq(2)
      end

      it 'sets the feature name' do
        expect(subject.features).to all(have_attributes :name => be_present)
      end

      it 'sets the feature type' do
        expect(subject.features).to all(have_attributes :feature_type => be_present)
      end

      it 'sets the feature metadata' do
       expect(subject.features).to all(have_attributes :metadata => include('prop0' => 'value'))
      end
    end

    describe '#cache_key' do
      it 'returns a string' do
        expect(subject.cache_key).to be_a(String)
      end
    end
  end

  context 'when given an empty object' do
    let(:data) { {} }

    describe '#features' do
      it 'returns empty records' do
        expect(subject.features.count).to eq(0)
      end
    end
  end

  context 'when given a blank object' do
    let(:data) { nil }

    describe '#features' do
      it 'returns empty records' do
        expect(subject.features.count).to eq(0)
      end
    end
  end
end
