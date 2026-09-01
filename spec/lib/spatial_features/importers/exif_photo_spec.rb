require 'spec_helper'

describe SpatialFeatures::Importers::ExifPhoto do
  let(:photo_path) { fixture_file_path('bc25_bt_0030.JPG') }

  subject(:features) do
    described_class.new(photo_path).features
  end

  describe '#features' do
    it 'imports one feature from a geotagged photo' do
      expect(features.count).to eq(1)
    end
    it 'places the feature at the EXIF GPS coordinates' do
      expect(features.first.geog).to eq(
        'POINT(-125.12249 50.36145)'
      )
    end
  end
end
