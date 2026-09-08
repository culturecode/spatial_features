require 'spec_helper'

describe SpatialFeatures::Importers::ExifPhoto do
  let(:photo_bytes) { File.binread(fixture_file_path('bc25_bt_0030.JPG')) }

  it 'preserves extracted photos whose ZIP paths match the former staging destination' do
    Dir.mktmpdir do |directory|
      archive = File.join(directory, 'photos.zip')
      entry = 'exif_photos/0/photo.JPG'
      Zip::OutputStream.open(archive) do |zip|
        zip.put_next_entry(entry)
        zip.write(photo_bytes)
      end
      archive_bytes = File.binread(archive)

      described_class.create_all(archive, tmpdir: directory) do |importers|
        extracted = File.join(directory, entry)
        staged = importers.first.instance_variable_get(:@data)
        expect(staged).not_to eq(extracted)
        expect(File.binread(extracted)).to eq(photo_bytes)
        expect(File.binread(staged)).to eq(photo_bytes)
        expect(importers.first.features.first.name).to eq('photo.JPG')
        expect(importers.first.source_identifier).to eq('photo.JPG')
      end

      expect(File.binread(archive)).to eq(archive_bytes)
    end
  end

  it 'does not overwrite an earlier staged photo when the caller reuses its directory' do
    Dir.mktmpdir do |directory|
      source = File.join(directory, 'photo.JPG')
      File.binwrite(source, photo_bytes)
      described_class.create_all(source, tmpdir: directory) do |first|
        first_path = first.first.features.first.importable_image_paths.first
        File.binwrite(source, photo_bytes + 'changed')

        described_class.create_all(source, tmpdir: directory) do |second|
          second_path = second.first.features.first.importable_image_paths.first
          expect(second_path).not_to eq(first_path)
          expect(File.binread(first_path)).to eq(photo_bytes)
          expect(File.binread(second_path)).to eq(photo_bytes + 'changed')
        end
      end
    end
  end
end
