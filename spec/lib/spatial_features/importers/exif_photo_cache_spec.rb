require 'spec_helper'

describe SpatialFeatures::Importers::ExifPhoto do
  let(:photo_bytes) { File.binread(fixture_file_path('bc25_bt_0030.JPG')) }

  around do |example|
    Dir.mktmpdir do |directory|
      @directory = directory
      example.run
    end
  end

  def photo(name, bytes = photo_bytes)
    File.join(@directory, name).tap { |path| File.binwrite(path, bytes) }
  end

  def key(path, **options)
    described_class.create_all(path, **options) { |importers| importers.first.cache_key }
  end

  def archive(name, entry)
    File.join(@directory, name).tap do |path|
      Zip::OutputStream.open(path) do |zip|
        zip.put_next_entry(entry)
        zip.write(photo_bytes)
      end
    end
  end

  it 'ignores random staging directories but detects changed photo bytes' do
    path = photo('photo.JPG')
    original_key = key(path)
    expect(key(path)).to eq(original_key)
    File.binwrite(path, photo_bytes + 'changed')
    expect(key(path)).not_to eq(original_key)
  end

  it 'detects a changed source identifier and a renamed photo with a fixed source identifier' do
    first = photo('first.JPG')
    second = photo('second.JPG')
    expect(key(first, source_identifier: 'survey')).not_to eq(key(first, source_identifier: 'other'))
    expect(key(first, source_identifier: 'survey')).not_to eq(key(second, source_identifier: 'survey'))
  end

  it 'refreshes persisted names and identifiers after a JPEG rename, then skips an unchanged import' do
    record = new_dummy_class do
      has_spatial_features import: { photo_source: :ExifPhoto }
      attr_accessor :photo_source
    end.create!
    record.photo_source = photo('first.JPG')
    record.update_features!
    old_hash = record.features_hash
    record.photo_source = photo('renamed.JPG')

    expect(record.update_features!).to be(true)
    expect(record.features_hash).not_to eq(old_hash)
    expect(record.features.reload.pluck(:name, :source_identifier)).to eq([['renamed.JPG', 'renamed.JPG']])
    expect(record.update_features!).to be_nil
  end

  it 'refreshes persisted names and identifiers when a ZIP entry is renamed' do
    record = new_dummy_class do
      has_spatial_features import: { photo_source: :ExifPhoto }
      attr_accessor :photo_source
    end.create!
    record.photo_source = archive('first.zip', 'survey/first.JPG')
    record.update_features!
    old_hash = record.features_hash
    record.photo_source = archive('second.zip', 'survey/renamed.JPG')

    expect(record.update_features!).to be(true)
    expect(record.features_hash).not_to eq(old_hash)
    expect(record.features.reload.pluck(:name, :source_identifier)).to eq([['renamed.JPG', 'renamed.JPG']])
    expect(record.update_features!).to be_nil
  end

  it 'ignores an outer ZIP rename when its photo names and contents are unchanged' do
    first = archive('first.zip', 'survey/photo.JPG')
    second = File.join(@directory, 'renamed.zip')
    FileUtils.cp(first, second)
    expect(key(second)).to eq(key(first))
  end
end
