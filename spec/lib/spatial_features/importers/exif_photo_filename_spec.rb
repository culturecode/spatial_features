require 'spec_helper'

describe SpatialFeatures::Importers::ExifPhoto do
  let(:photo_bytes) { File.binread(fixture_file_path('bc25_bt_0030.JPG')) }

  def remote_body(url, bytes)
    allow(URI).to receive(:open).with(url, anything).and_return(StringIO.new(bytes))
  end

  it 'preserves the URL filename throughout staging and feature creation with one download' do
    url = 'https://example.test/survey/shoreline.JPG'
    remote_body(url, photo_bytes)

    described_class.create_all(url) do |importers|
      importer = importers.first
      feature = importer.features.first
      path = feature.importable_image_paths.first

      expect(File.basename(path)).to eq('shoreline.JPG')
      expect(feature.name).to eq('shoreline.JPG')
      expect(importer.source_identifier).to eq('shoreline.JPG')
      expect(File.binread(path)).to eq(photo_bytes)
    end

    expect(URI).to have_received(:open).once
  end

  it 'decodes the URL path without including query parameters or converting plus signs to spaces' do
    url = 'https://example.test/flight%20line+1.JPG?download=1#preview'
    remote_body(url, photo_bytes)

    described_class.create_all(url) do |importers|
      feature = importers.first.features.first
      expect(feature.name).to eq('flight line+1.JPG')
      expect(File.basename(feature.importable_image_paths.first)).to eq('flight line+1.JPG')
    end
  end

  it 'preserves the filename used to identify a GPS-less remote photo' do
    url = 'https://example.test/no-gps.JPG'
    remote_body(url, photo_bytes)
    allow(EXIFR::JPEG).to receive(:new).and_return(double(gps: nil))

    described_class.create_all(url) do |importers|
      expect(importers.first.features).to be_empty
      expect(importers.first.source_identifier).to eq('no-gps.JPG')
      expect(importers.first.warnings).to include(a_string_matching(/GPS/))
    end
  end

  it 'uses ZIP entry names even when a one-photo archive URL looks like a JPEG' do
    Dir.mktmpdir do |directory|
      archive = File.join(directory, 'single.zip')
      Zip::OutputStream.open(archive) do |zip|
        zip.put_next_entry('survey/actual-photo.JPG')
        zip.write(photo_bytes)
      end
      url = 'https://example.test/misleading.JPG'
      remote_body(url, File.binread(archive))

      described_class.create_all(url) do |importers|
        expect(importers.length).to eq(1)
        expect(importers.first.features.first.name).to eq('actual-photo.JPG')
      end
    end
  end

  it 'keeps a decoded filename inside the staging directory' do
    url = 'https://example.test/..%2F..%5Cphoto.JPG'
    remote_body(url, photo_bytes)

    described_class.create_all(url) do |importers|
      path = importers.first.features.first.importable_image_paths.first
      expect(File.basename(path)).to eq('photo.JPG')
      expect(File.binread(path)).to eq(photo_bytes)
    end
  end
end
