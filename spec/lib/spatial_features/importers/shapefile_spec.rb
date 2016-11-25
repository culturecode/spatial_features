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
    end
  end
end
