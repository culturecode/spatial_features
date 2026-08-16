require 'spec_helper'

describe SpatialFeatures::Importers::ESRIGeoJSON do
  let(:url) { 'https://example.com/arcgis/rest/services/Layer/MapServer/0/query?f=geojson&where=1%3D1' }

  # A page of the shape an ArcGIS `f=geojson` query returns. `exceeded` sets the flag the
  # service uses to say more features are waiting.
  def page(count, exceeded: false, start: 0, nested_flag: false)
    features = Array.new(count) do |i|
      n = start + i
      { 'type' => 'Feature',
        'properties' => { 'name' => "Area #{n}", 'prop0' => 'value' },
        'geometry' => { 'type' => 'Polygon',
                        'coordinates' => [[[n, 20], [n + 1, 20], [n + 1, 21], [n, 21], [n, 20]]] } }
    end

    collection = { 'type' => 'FeatureCollection', 'features' => features }
    if exceeded
      nested_flag ? collection['properties'] = { 'exceededTransferLimit' => true }
                  : collection['exceededTransferLimit'] = true
    end
    StringIO.new(JSON.dump(collection))
  end

  # A page of the shape an ArcGIS `f=json` query returns, which is ESRI JSON rather than
  # GeoJSON: attributes instead of properties, rings instead of coordinates, and the geometry
  # type declared once for the collection. OGR reads it by sniffing the content.
  def esri_page(count, exceeded: false)
    features = Array.new(count) do |i|
      { 'attributes' => { 'name' => "Area #{i}", 'prop0' => 'value' },
        'geometry' => { 'rings' => [[[i, 20], [i + 1, 20], [i + 1, 21], [i, 21], [i, 20]]] } }
    end

    collection = { 'displayFieldName' => 'name',
                   'geometryType' => 'esriGeometryPolygon',
                   'spatialReference' => { 'wkid' => 4326 },
                   'fields' => [{ 'name' => 'name', 'type' => 'esriFieldTypeString', 'length' => 50 },
                                { 'name' => 'prop0', 'type' => 'esriFieldTypeString', 'length' => 50 }],
                   'features' => features }
    collection['exceededTransferLimit'] = true if exceeded
    StringIO.new(JSON.dump(collection))
  end

  # Answers each request in turn, recording the URLs it was asked for.
  def stub_pages(*pages)
    requested = []
    allow(URI).to receive(:open) do |requested_url|
      requested << requested_url
      pages.shift || raise("requested more pages than the stub was given: #{requested_url}")
    end
    requested
  end

  describe '#features' do
    context 'when the response fits in a single page' do
      it 'returns the features and makes one request' do
        requested = stub_pages(page(3))

        expect(subject_for(url).features.count).to eq(3)
        expect(requested.length).to eq(1)
        expect(requested.first).to eq(url)
      end
    end

    context 'when the response is capped at maxRecordCount' do
      it 'walks the pages and returns every feature' do
        requested = stub_pages(page(2, :exceeded => true), page(2, :exceeded => true, :start => 2), page(1, :start => 4))

        expect(subject_for(url).features.count).to eq(5)
        expect(requested.length).to eq(3)
      end

      it 'asks for each page by resultOffset' do
        requested = stub_pages(page(2, :exceeded => true), page(1, :start => 2))

        subject_for(url).features

        expect(requested[0]).not_to include('resultOffset')
        expect(requested[1]).to include('resultOffset=2')
      end

      it 'keeps the query the caller supplied' do
        requested = stub_pages(page(2, :exceeded => true), page(1, :start => 2))

        subject_for(url).features

        expect(requested[1]).to include('f=geojson')
        expect(requested[1]).to include('where=1%3D1')
      end

      it 'recognises the flag when the service nests it under properties' do
        requested = stub_pages(page(2, :exceeded => true, :nested_flag => true), page(1, :start => 2))

        expect(subject_for(url).features.count).to eq(3)
        expect(requested.length).to eq(2)
      end
    end

    context 'when the service ignores resultOffset' do
      it 'gives up rather than paginating forever' do
        allow(URI).to receive(:open) { page(2, :exceeded => true) }

        expect { subject_for(url).features }
          .to raise_exception(SpatialFeatures::ImportError, /still reporting more features/i)
      end

      it 'gives up after `max_pages` requests' do
        requested = []
        allow(URI).to receive(:open) do |requested_url|
          requested << requested_url
          page(2, :exceeded => true)
        end
        allow(SpatialFeatures::Importers::ESRIGeoJSON).to receive(:max_pages).and_return(3)

        expect { subject_for(url).features }.to raise_exception(SpatialFeatures::ImportError)
        expect(requested.length).to eq(3)
      end
    end

    context 'when the service replies with something other than a feature collection' do
      it 'raises rather than surfacing a parse error' do
        allow(URI).to receive(:open).and_return(StringIO.new('<html><body>Forbidden</body></html>'))

        expect { subject_for(url).features }
          .to raise_exception(SpatialFeatures::ImportError, /did not return map data/i)
      end
    end

    context 'when the service cannot be reached' do
      it 'raises for an HTTP error status' do
        allow(URI).to receive(:open)
          .and_raise(OpenURI::HTTPError.new('404 Not Found', StringIO.new))

        expect { subject_for(url).features }
          .to raise_exception(SpatialFeatures::ImportError, /could not be reached/i)
      end

      it 'raises when the connection times out' do
        allow(URI).to receive(:open).and_raise(Net::ReadTimeout)

        expect { subject_for(url).features }
          .to raise_exception(SpatialFeatures::ImportError, /could not be reached/i)
      end

      it 'bounds each request with `Download.timeout`' do
        allow(SpatialFeatures::Download).to receive(:timeout).and_return(7)
        expect(URI).to receive(:open)
          .with(url, :open_timeout => 7, :read_timeout => 7)
          .and_return(page(1))

        subject_for(url).features
      end
    end

    context 'when the service answers in ESRI JSON rather than GeoJSON' do
      let(:url) { 'https://example.com/arcgis/rest/services/Layer/MapServer/0/query?f=json&where=1%3D1' }

      it 'returns the features' do
        stub_pages(esri_page(2))

        expect(subject_for(url).features.count).to eq(2)
      end

      it 'carries the attributes through as metadata' do
        stub_pages(esri_page(2))

        expect(subject_for(url).features).to all(have_attributes(:metadata => include('prop0' => 'value')))
      end

      it 'walks the pages the same way' do
        requested = stub_pages(esri_page(2, :exceeded => true), esri_page(1))

        expect(subject_for(url).features.count).to eq(3)
        expect(requested.length).to eq(2)
        expect(requested[1]).to include('resultOffset=2')
      end
    end

    context 'when given a local path containing shell metacharacters' do
      # `URI.parse` rejects a path holding a quote or a space, so the payload has to be one it
      # accepts: `$IFS` stands in for the space, and `$(...)` is what a shell would expand
      # inside the double quotes a command string wraps a path in.
      it 'does not run the injected command' do
        marker = ::File.join(Dir.mktmpdir, 'injected')

        subject_for("/tmp/x$(touch$IFS#{marker}).json").features rescue nil

        expect(::File.exist?(marker)).to be false
      end
    end

    context 'when given a local file path' do
      it 'reads the file without downloading it' do
        expect(URI).not_to receive(:open)

        expect(subject_for(fixture_file_path('geo.json')).features).to be_present
      end
    end

  end

  def subject_for(data)
    SpatialFeatures::Importers::ESRIGeoJSON.new(data)
  end
end
