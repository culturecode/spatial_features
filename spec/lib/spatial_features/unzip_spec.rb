require 'spec_helper'

describe SpatialFeatures::Unzip do
  describe '::extract' do
    # `::extract` resolves the destination before extracting into it, so it returns real
    # paths. On macOS the temp directory is reached through a symlink.
    let(:tmpdir) { File.realpath(Dir.mktmpdir) }

    def archive_with_entry_named(name)
      path = ::File.join(Dir.mktmpdir, 'archive.zip')
      Zip::OutputStream.open(path) do |zos|
        zos.put_next_entry(name)
        zos.write('contents')
      end
      path
    end

    it 'extracts entries below the destination directory' do
      paths = SpatialFeatures::Unzip.extract(archive_with_entry_named('layers/data.shp'), tmpdir: tmpdir)

      expect(paths).to contain_exactly("#{tmpdir}/layers/data.shp")
    end

    # `IGNORED_ENTRY_PATHS` turns this name away before `::contained_path` sees it, so this
    # covers the pair of them. The `::contained_path` specs below cover the check itself.
    it 'does not extract an entry whose name climbs out of the destination directory' do
      paths = SpatialFeatures::Unzip.extract(archive_with_entry_named('layers/../../escaped.shp'), tmpdir: tmpdir)

      expect(paths).to be_empty
      expect(::File.exist?(::File.expand_path("#{tmpdir}/../../escaped.shp"))).to be false
    end

    # `::contained_path` compares against the destination lexically, so it can only vouch for
    # a destination that is already a real path. These two hold that up.

    it 'resolves a destination reached through a symlink' do
      link = ::File.join(Dir.mktmpdir, 'link')
      ::File.symlink(tmpdir, link)

      paths = SpatialFeatures::Unzip.extract(archive_with_entry_named('layers/data.shp'), tmpdir: link)

      expect(paths).to contain_exactly("#{tmpdir}/layers/data.shp")
    end

    # Asserting on the returned paths rather than on the filesystem: rubyzip declines to
    # create a symlink on extract, so no filesystem assertion here can tell our skip from
    # rubyzip's. Only the returned paths change when the skip is removed.
    it 'does not extract symlink entries' do
      paths = SpatialFeatures::Unzip.extract(fixture_file_path('archive_with_symlink.zip'), tmpdir: tmpdir)

      expect(paths).to contain_exactly("#{tmpdir}/layers/", "#{tmpdir}/layers/data.shp")
    end
  end

  describe '::contained_path' do
    let(:root) { Pathname.new(File.realpath(Dir.mktmpdir)).join('root') }

    it 'returns where the entry lands' do
      expect(SpatialFeatures::Unzip.send(:contained_path, root, 'layers/data.shp')).to eq("#{root}/layers/data.shp")
    end

    it 'keeps the trailing separator that marks a directory entry' do
      expect(SpatialFeatures::Unzip.send(:contained_path, root, 'layers/')).to eq("#{root}/layers/")
    end

    it 'returns nil for a name that climbs out' do
      expect(SpatialFeatures::Unzip.send(:contained_path, root, '../escaped.shp')).to be_nil
      expect(SpatialFeatures::Unzip.send(:contained_path, root, 'layers/../../escaped.shp')).to be_nil
    end

    # `IGNORED_ENTRY_PATHS` turns away the names that climb out, but an absolute name starts
    # with neither a dot nor `__macosx`, so this check is the only thing that rejects it.
    it 'returns nil for an absolute name' do
      expect(SpatialFeatures::Unzip.send(:contained_path, root, '/etc/passwd')).to be_nil
    end

    it 'returns nil for a name that reaches a sibling whose path shares the prefix' do
      expect(SpatialFeatures::Unzip.send(:contained_path, root, '../root-evil/escaped.shp')).to be_nil
    end
  end
end
