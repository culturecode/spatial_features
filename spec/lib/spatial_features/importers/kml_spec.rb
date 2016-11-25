require 'spec_helper'

describe SpatialFeatures::Importers::KML do
  subject { SpatialFeatures::Importers::KML.new(data) }

  context 'when given a string of KML' do
    let(:data) { kml_file.read }

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
        expect(subject.features).to all(have_attributes :metadata => be_present)
      end
    end
  end
end
