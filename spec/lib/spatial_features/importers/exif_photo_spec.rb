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

  describe '#cache_key' do
    it 'is based on the photo contents rather than its path' do
      expect(importer.cache_key).to eq(Digest::MD5.file(photo_path).hexdigest)
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

  context 'when the JPEG is malformed' do
    before do
      allow(EXIFR::JPEG).to receive(:new).with(photo_path).and_raise(EXIFR::MalformedJPEG)
    end

    it 'raises an import error with a useful message' do
      expect { features }
        .to raise_error(SpatialFeatures::ImportError, /photo couldn't be read/i)
    end
  end

  describe '.create_all' do
    let(:tmpdir) { Dir.mktmpdir }

    after do
      FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir)
    end

    context 'with an individual JPEG' do
      it 'creates one importer' do
        importers = described_class.create_all(photo_path, tmpdir: tmpdir)

        expect(importers.count).to eq(1)
        expect(importers.first.features.count).to eq(1)
      end
    end

    context 'with a ZIP of JPEGs' do
      subject(:importers) do
        described_class.create_all(fixture_file_path('sample_photos.zip'), tmpdir: tmpdir)
      end

      it 'creates one importer per photo' do
        expect(importers.count).to eq(5)
      end

      it 'imports one distinct point per photo' do
        features = importers.flat_map(&:features)

        expect(features.count).to eq(5)
        expect(features.map(&:geog).uniq.count).to eq(5)
      end

      it 'preserves each photo filename' do
        expect(importers.map(&:source_identifier)).to contain_exactly(
          'bc25_bt_0030.JPG',
          'bc25_bt_0031.JPG',
          'bc25_bt_0032.JPG',
          'bc25_bt_0033.JPG',
          'bc25_bt_0034.JPG'
        )
      end

      it 'keeps every extracted photo available to image handlers' do
        image_paths = importers.flat_map(&:features).flat_map(&:importable_image_paths)

        expect(image_paths.count).to eq(5)
        expect(image_paths.all? {|path| ::File.file?(path) }).to be(true)
      end
    end

    context 'with a ZIP containing no JPEGs' do
      it 'reports that the archive has no photos' do
        expect do
          described_class.create_all(fixture_file_path('archive_without_any_known_file.zip'), tmpdir: tmpdir)
        end.to raise_error(SpatialFeatures::ImportError, /JPEG photos/i)
      end
    end
  end
end
