require 'spec_helper'

describe SpatialFeatures::Importers::ExifPhoto do
  let(:photo_path) { fixture_file_path('bc25_bt_0030.JPG') }
  let(:archive_path) { fixture_file_path('sample_photos.zip') }
  let(:temporary_root) { Dir.mktmpdir }

  before do
    root = temporary_root
    allow(Dir).to receive(:tmpdir).and_return(root)
  end

  after do
    FileUtils.remove_entry(temporary_root)
  end

  it 'keeps a standalone photo available until its importer is closed' do
    importer = described_class.create_all(photo_path).first
    feature = importer.features.first
    path = feature.importable_image_paths.first
    GC.start

    expect(feature.name).to eq('bc25_bt_0030.JPG')
    expect(File.binread(path)).to eq(File.binread(photo_path))
    expect(importer.cache_key).to eq(Digest::MD5.file(photo_path).hexdigest)

    importer.close
    importer.close

    expect(File.exist?(path)).to be(false)
    expect(File.exist?(photo_path)).to be(true)
    expect(Dir.children(temporary_root)).to be_empty
  end

  it 'also owns its storage when tmpdir is explicitly nil' do
    described_class.create_all(photo_path, tmpdir: nil) do |importers|
      expect(importers.first.features.length).to eq(1)
    end

    expect(Dir.children(temporary_root)).to be_empty
  end

  it 'keeps every ZIP photo readable in the block and cleans up after returning its result' do
    result = described_class.create_all(archive_path) do |importers|
      features = importers.flat_map(&:features)
      paths = features.flat_map(&:importable_image_paths)

      expect(paths.length).to eq(5)
      expect(paths.map { |path| File.size(path) }).to all(be_positive)
      features.map(&:name)
    end

    expect(result).to contain_exactly(*(30..34).map { |number| "bc25_bt_00#{number}.JPG" })
    expect(Dir.children(temporary_root)).to be_empty
    expect(File.exist?(archive_path)).to be(true)
  end

  it 'does not remove other ZIP photos when one importer is closed' do
    importers = described_class.create_all(archive_path)
    paths = importers.flat_map(&:features).flat_map(&:importable_image_paths)

    importers.first.close

    expect(File.exist?(paths.first)).to be(false)
    expect(paths.drop(1).map { |path| File.size(path) }).to all(be_positive)
    importers.drop(1).each(&:close)
    expect(Dir.children(temporary_root)).to be_empty
  end

  it 'cleans up all owned photos when the consumer raises' do
    expect do
      described_class.create_all(archive_path) do |importers|
        path = importers.first.features.first.importable_image_paths.first
        expect(File.size(path)).to be_positive
        raise IOError, 'image handler failed'
      end
    end.to raise_error(IOError, 'image handler failed')

    expect(Dir.children(temporary_root)).to be_empty
  end

  it 'cleans up earlier and partially staged photos when staging fails' do
    count = 0
    allow(IO).to receive(:copy_stream).and_wrap_original do |method, *args|
      count += 1
      raise IOError, 'second photo failed' if count == 2

      method.call(*args)
    end

    expect { described_class.create_all(archive_path) }.to raise_error(IOError, 'second photo failed')

    expect(Dir.children(temporary_root)).to be_empty
  end

  it 'does not reinterpret a missing-path error raised by the consumer' do
    expect do
      described_class.create_all(photo_path) do |_importers|
        raise SpatialFeatures::Unzip::PathNotFound, 'consumer path missing'
      end
    end.to raise_error(SpatialFeatures::Unzip::PathNotFound, 'consumer path missing')

    expect(Dir.children(temporary_root)).to be_empty
  end

  it 'cleans up when the archive has no photos' do
    expect do
      described_class.create_all(fixture_file_path('archive_without_any_known_file.zip'))
    end.to raise_error(SpatialFeatures::ImportError, /JPEG photos/i)

    expect(Dir.children(temporary_root)).to be_empty
  end

  it 'cleans up a photo that has no GPS coordinates' do
    allow(EXIFR::JPEG).to receive(:new).and_return(double(gps: nil))

    described_class.create_all(photo_path) do |importers|
      expect(importers.first.features).to be_empty
      expect(importers.first.warnings).to include(a_string_matching(/GPS/))
    end

    expect(Dir.children(temporary_root)).to be_empty
  end

  it 'leaves caller-managed storage available after the block' do
    paths = described_class.create_all(archive_path, tmpdir: temporary_root) do |importers|
      importers.flat_map(&:features).flat_map(&:importable_image_paths)
    end

    expect(paths.map { |path| File.size(path) }).to all(be_positive)
    expect(Dir.exist?(temporary_root)).to be(true)
  end

  it 'creates a supplied directory when it does not exist yet' do
    directory = File.join(temporary_root, 'caller-managed')
    paths = described_class.create_all(archive_path, tmpdir: directory) do |importers|
      importers.flat_map(&:features).flat_map(&:importable_image_paths)
    end

    expect(paths.length).to eq(5)
    expect(paths.map { |path| File.size(path) }).to all(be_positive)
    expect(Dir.exist?(directory)).to be(true)
  end

  it 'keeps a permanent copy after its staged source is cleaned up' do
    destination = File.join(temporary_root, 'permanent.JPG')
    described_class.create_all(photo_path) do |importers|
      path = importers.first.features.first.importable_image_paths.first
      FileUtils.cp(path, destination)
    end

    expect(File.binread(destination)).to eq(File.binread(photo_path))
    expect(Dir.children(temporary_root)).to eq(['permanent.JPG'])
  end

  it 'does not remove caller-managed storage when the consumer raises' do
    paths = []
    expect do
      described_class.create_all(photo_path, tmpdir: temporary_root) do |importers|
        paths = importers.first.features.first.importable_image_paths
        raise IOError, 'image handler failed'
      end
    end.to raise_error(IOError, 'image handler failed')

    expect(paths.map { |path| File.size(path) }).to all(be_positive)
  end
end
