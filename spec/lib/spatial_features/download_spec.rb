require 'spec_helper'

describe SpatialFeatures::Download do
  # `Kernel#open` runs its argument as a command when the string begins with a pipe, so a
  # source name that reaches it is a command the caller never intended to run.
  describe 'a source name beginning with a pipe' do
    let(:marker) { ::File.join(Dir.mktmpdir, 'executed') }

    it 'is not run as a command by ::open' do
      SpatialFeatures::Download.open("|touch #{marker}") rescue nil

      expect(::File.exist?(marker)).to be false
    end

    it 'is not run as a command by ::entries' do
      SpatialFeatures::Download.entries("|touch #{marker}") rescue nil

      expect(::File.exist?(marker)).to be false
    end

    it 'is not run as a command by ::read' do
      SpatialFeatures::Download.read("|touch #{marker}") rescue nil

      expect(::File.exist?(marker)).to be false
    end
  end

  describe '::read' do
    it 'returns the body of a remote source' do
      allow(URI).to receive(:open).and_return(StringIO.new('body'))

      expect(SpatialFeatures::Download.read('https://example.com/layer.json')).to eq('body')
    end

    it 'bounds the request with `timeout`' do
      allow(SpatialFeatures::Download).to receive(:timeout).and_return(9)
      expect(URI).to receive(:open)
        .with('https://example.com/layer.json', :open_timeout => 9, :read_timeout => 9)
        .and_return(StringIO.new('body'))

      SpatialFeatures::Download.read('https://example.com/layer.json')
    end

    it 'raises when the source cannot be reached' do
      allow(URI).to receive(:open).and_raise(SocketError.new('getaddrinfo failed'))

      expect { SpatialFeatures::Download.read('https://example.com/layer.json') }
        .to raise_exception(SpatialFeatures::ImportError, /could not be reached/i)
    end
  end

  describe '::open_each' do
    # A remote source is held in a `Tempfile`, which unlinks its path once it is garbage
    # collected. Callers keep the returned file and read its path later (a cache key, a
    # feature import), so the returned object has to be the one that owns the path.
    shared_examples 'a source whose path outlives garbage collection' do
      it 'returns the file that owns the temporary path' do
        file = SpatialFeatures::Download.open_each('https://example.com/photo.jpg').first
        expect(file).to be_a(Tempfile)
      end

      it 'keeps the path readable after garbage collection' do
        file = SpatialFeatures::Download.open_each('https://example.com/photo.jpg').first
        GC.start

        expect(::File.read(file.path)).to eq('body')
      end
    end

    context 'with a small remote body, which open-uri returns as a StringIO' do
      before { allow(URI).to receive(:open).and_return(StringIO.new('body')) }

      it_behaves_like 'a source whose path outlives garbage collection'
    end

    context 'with a large remote body, which open-uri returns as a Tempfile' do
      before do
        allow(URI).to receive(:open).and_return(Tempfile.new('open-uri').tap {|t| t.write('body'); t.rewind })
      end

      it_behaves_like 'a source whose path outlives garbage collection'
    end

    it 'opens each matching entry of an archive by path' do
      files = SpatialFeatures::Download.open_each(fixture_file_path('archive_with_multiple_kmls.zip'), unzip: [/\.kml$/])

      expect(files.length).to be > 1
      expect(files).to all(be_a(::File))
      expect(files.map(&:path)).to all(end_with('.kml'))
    end
  end

  describe '::open' do
    # A missing local file is an `Errno::ENOENT`, which is a `SystemCallError` and so would be
    # caught by the unreachable rescue if that rescue covered local paths. Callers turn it into
    # a message for the person who uploaded the file, and that message must not name the path
    # the server looked in.
    it 'lets a missing local path raise Errno::ENOENT rather than reporting it as unreachable' do
      expect { SpatialFeatures::Download.open('/nonexistent/path/to/upload.zip') }
        .to raise_exception(Errno::ENOENT)
    end
  end
end
