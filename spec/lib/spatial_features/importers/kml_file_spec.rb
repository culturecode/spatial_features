require 'spec_helper'

describe SpatialFeatures::Importers::KMLFile do
  shared_examples_for 'kml importer' do |data|
    subject { SpatialFeatures::Importers::KMLFile.new(data) }

    describe '#features' do
      it 'returns all records' do
        expect(subject.features.count).to eq(2)
      end

      it 'sets the feature name' do
        expect(subject.features).to all(have_attributes :name => be_present)
      end

      it 'sets the feature metadata' do
        expect(subject.features).to all(have_attributes :metadata => be_present)
      end
    end
  end

  shared_examples_for 'kml importer without placemarks' do |data|
    subject { SpatialFeatures::Importers::KMLFile.new(data) }

    describe '#features' do
      it 'returns all records' do
        expect(subject.features.count).to eq(2)
      end

      it 'does not set the feature name' do
        expect(subject.features).to all(have_attributes :name => be_blank)
      end

      it 'does not set the feature metadata' do
        expect(subject.features).to all(have_attributes :metadata => {})
      end
    end
  end

  shared_examples_for 'kml importer with an invalid placemark' do |data|
    subject { SpatialFeatures::Importers::KMLFile.new(data) }

    describe '#features' do
      it 'returns all valid records' do
        expect(subject.features.count).to eq(2)
      end

      it 'sets the feature name' do
        expect(subject.features).to all(have_attributes :name => be_present)
      end

      it 'sets the feature metadata' do
        expect(subject.features).to all(have_attributes :metadata => be_present)
      end
    end
  end

  shared_examples_for 'kml importer with unimportable file' do |data|
    subject { SpatialFeatures::Importers::KMLFile.new(data) }

    describe '#features' do
      it 'raises an exception' do
        expect { subject.features }.to raise_exception(SpatialFeatures::ImportError)
      end
    end
  end

  shared_examples_for 'kml importer without any features' do |data|
    subject { SpatialFeatures::Importers::KMLFile.new(data) }

    describe '#features' do
      it 'has no valid records' do
        expect(subject.features.count).to eq(0)
      end
    end
  end

  context 'when given a path to a KML file' do
    it_behaves_like 'kml importer', kml_file.path
  end

  context 'when given KML file' do
    it_behaves_like 'kml importer', kml_file
  end

  context 'when given KML file without features' do
    it_behaves_like 'kml importer without any features', kml_file_without_features
  end

  context 'when given KMZ file' do
    it_behaves_like 'kml importer', kmz_file
  end

  context 'when given KML file with valid altitude' do
    it_behaves_like 'kml importer', kml_file_with_altitude
  end

  context 'when given KML file with invalid altitude' do
    it_behaves_like 'kml importer', kml_file_with_invalid_altitude
  end

  context 'when given KMZ file with features but no placemarks' do
    it_behaves_like 'kml importer without placemarks', kmz_file_features_without_placemarks
  end

  context 'when given KMZ file with an invalid placemark' do
    it_behaves_like 'kml importer with an invalid placemark', kml_file_with_invalid_placemark
  end

  context 'when given KML with a NetworkLink' do
    it_behaves_like 'kml importer with unimportable file', kml_file_with_network_link
  end
end
