require 'spec_helper'

describe SpatialFeatures::Importers::ExifPhoto do
  let(:photo_path) { fixture_file_path('bc25_bt_0030.JPG') }

  subject(:importer) { described_class.new(photo_path) }

  let(:features) { importer.features }

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

  context 'when the photo has no GPS coordinates' do
    before do
      allow(EXIFR::JPEG).to receive(:new).with(photo_path).and_return(double(gps: nil))
    end

    it 'does not import a feature' do
      expect(features).to be_empty
    end

    it 'records a warning that identifies the problem' do
      features

      expect(importer.warnings).to include(a_string_matching(/GPS coordinates/i))
    end

    it 'identifies the source photo by filename' do
      expect(importer.source_identifier).to eq('bc25_bt_0030.JPG')
    end
  end

  context 'when optional EXIF metadata is absent' do
    let(:gps) { double(latitude: 50.36145, longitude: -125.12249, altitude: nil) }
    let(:photo) { double(gps: gps, date_time_original: nil, model: nil) }

    before do
      allow(EXIFR::JPEG).to receive(:new).with(photo_path).and_return(photo)
    end

    it 'imports the point without blank metadata values' do
      expect(features.first.metadata).to eq({})
    end
  end
end
