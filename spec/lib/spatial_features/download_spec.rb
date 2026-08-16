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
