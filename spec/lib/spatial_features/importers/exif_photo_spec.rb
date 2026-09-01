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

    it 'includes EXIF metadata' do
    expect(features.first.metadata).to eq(
      'capture_time' => '2025-08-08 16:48:16',
      'altitude' => '109.4',
      'camera_model' => 'NIKON D7500'
    )
    end

    it 'makes the photo available for attachment importing' do
      expect(features.first.importable_image_paths).to eq([photo_path])
    end
  end
end
