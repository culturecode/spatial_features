require 'spec_helper'

describe SpatialFeatures::Importers::KMLFileArcGIS do
  shared_examples_for 'kml importer' do |url|
    subject { SpatialFeatures::Importers::KMLFileArcGIS.new(url) }

    describe '#features' do
      it 'returns all records' do
        allow(SpatialFeatures::Download).to receive(:open).and_return(Kernel.open(kmz_file))
        expect(subject.features.count).to eq(2)
      end
    end
  end

  context 'when given an arcgis url' do
    it_behaves_like 'kml importer', 'http://jack:6080/kmz'
  end
end
