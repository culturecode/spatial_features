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
      subject(:created_importer) do
        described_class.create_all(photo_path, tmpdir: tmpdir).first
      end

      it 'creates one importer from a staged copy' do
        staged_path = created_importer.features.first.importable_image_paths.first

        expect(created_importer.features.count).to eq(1)
        expect(staged_path).to eq(::File.join(tmpdir, 'exif_photos', '0', 'bc25_bt_0030.JPG'))
        expect(staged_path).not_to eq(photo_path)
        expect(::File.binread(staged_path)).to eq(::File.binread(photo_path))
      end

      it 'keeps the original filename for the feature and source identifier' do
        expect(created_importer.source_identifier).to eq('bc25_bt_0030.JPG')
        expect(created_importer.features.first.name).to eq('bc25_bt_0030.JPG')
      end
    end

    context 'when the source path is unlinked while its file is still open' do
      it 'stages the JPEG from the open file descriptor and closes it' do
        owner = Tempfile.new(['remote-photo', '.JPG'])
        owner.binmode
        owner.write(::File.binread(photo_path))
        owner.flush
        open_file = ::File.open(owner.path, 'rb')
        owner.close!

        expect(::File.exist?(open_file.path)).to be(false)
        allow(SpatialFeatures::Download).to receive(:open).and_return(open_file)
        allow(SpatialFeatures::Download).to receive(:open_each).and_return([open_file])

        created_importer = described_class.create_all('https://example.test/photo.JPG', tmpdir: tmpdir).first
        staged_path = created_importer.features.first.importable_image_paths.first

        expect(open_file).to be_closed
        expect(created_importer.cache_key).to eq(Digest::MD5.file(photo_path).hexdigest)
        expect(created_importer.features.count).to eq(1)
        expect(::File.binread(staged_path)).to eq(::File.binread(photo_path))
      ensure
        open_file&.close unless open_file&.closed?
        owner&.close!
      end
    end

    context 'when staging the photo fails' do
      it 'still closes every source file' do
        source_files = Array.new(2) { ::File.open(photo_path, 'rb') }
        allow(SpatialFeatures::Download).to receive(:open_each).and_return(source_files)
        allow(IO).to receive(:copy_stream).and_raise(IOError, 'copy failed')

        expect do
          described_class.create_all(photo_path, tmpdir: tmpdir)
        end.to raise_error(IOError, 'copy failed')
        expect(source_files).to all(be_closed)
      ensure
        source_files&.each {|file| file.close unless file.closed? }
      end
    end

    context 'with an in-memory remote JPEG' do
      it 'remains available after the download temporary object is collected' do
        bytes = ::File.binread(photo_path)
        allow(URI).to receive(:open).and_return(StringIO.new(bytes))

        created_importer = described_class.create_all('https://example.test/photo.JPG', tmpdir: tmpdir).first
        GC.start
        staged_path = created_importer.features.first.importable_image_paths.first

        expect(created_importer.cache_key).to eq(Digest::MD5.hexdigest(bytes))
        expect(created_importer.features.count).to eq(1)
        expect(::File.file?(staged_path)).to be(true)
        expect(::File.binread(staged_path)).to eq(bytes)
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

      it 'stages every photo below the managed temporary directory' do
        image_paths = importers.flat_map(&:features).flat_map(&:importable_image_paths)

        expect(image_paths).to all(start_with("#{tmpdir}/exif_photos/"))
      end
    end

    context 'with duplicate filenames in different ZIP directories' do
      let(:archive_path) do
        ::File.join(tmpdir, 'duplicate_names.zip').tap do |path|
          bytes = ::File.binread(photo_path)
          Zip::OutputStream.open(path) do |zip|
            zip.put_next_entry('first/repeated.JPG')
            zip.write(bytes)
            zip.put_next_entry('second/repeated.JPG')
            zip.write(bytes)
          end
        end
      end

      it 'keeps both photos without changing their displayed filename' do
        importers = described_class.create_all(archive_path, tmpdir: tmpdir)
        image_paths = importers.flat_map(&:features).flat_map(&:importable_image_paths)

        expect(importers.map(&:source_identifier)).to eq(['repeated.JPG', 'repeated.JPG'])
        expect(importers.flat_map(&:features).map(&:name)).to eq(['repeated.JPG', 'repeated.JPG'])
        expect(image_paths.map {|path| ::File.basename(path) }).to eq(['repeated.JPG', 'repeated.JPG'])
        expect(image_paths.uniq.count).to eq(2)
        expect(image_paths.map {|path| ::File.binread(path) }).to all(eq(::File.binread(photo_path)))
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
