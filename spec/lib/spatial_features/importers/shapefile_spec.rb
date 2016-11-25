require 'spec_helper'

describe SpatialFeatures::Importers::KML do
  subject { SpatialFeatures::Importers::Shapefile.new(data) }

  context 'when given a shapefile' do
    let(:data) { shapefile }

    describe '#features' do
      it 'returns all records' do
        expect(subject.features.count).to eq(17)
      end

      it 'sets the feature metadata' do
        expect(subject.features).to all(have_attributes :metadata => be_present)
      end

      it 'sets the feature_type' do
        expect(subject.features).to all(have_attributes :feature_type => be_present)
      end
    end

    describe '#cache_key' do
      it 'returns a string' do
        expect(subject.cache_key).to be_a(String)
      end

      it 'changes if the records are different' do

      end
    end
  end
end
