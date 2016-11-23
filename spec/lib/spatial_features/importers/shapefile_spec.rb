require 'spec_helper'

describe SpatialFeatures::Importers::KML do
  subject { SpatialFeatures::Importers::KML.new(data) }

  context 'when given a shapefile' do
    # let(:data) { File.read("#{__dir__}/../../../../spec/fixtures/test.kml") }

    describe '#features' do
      it 'returns all records'
      it 'sets the feature metadata'
    end
  end
end
