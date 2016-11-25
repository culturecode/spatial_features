require 'spec_helper'

describe SpatialFeatures::Importers::KML do
  shared_examples_for 'kml importer' do |data|
    subject { SpatialFeatures::Importers::KMLFile.new(data) }

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

  context 'when given a path to a KML file' do
    it_behaves_like 'kml importer', kml_file.path
  end

  context 'when given KML file' do
    it_behaves_like 'kml importer', kml_file
  end

  context 'when given KMZ file' do
    it_behaves_like 'kml importer', kmz_file
  end
end
