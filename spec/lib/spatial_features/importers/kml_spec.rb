require 'spec_helper'

describe SpatialFeatures::Importers::KML do
  subject { SpatialFeatures::Importers::KML.new(data) }

  context 'when given a string of KML' do
    let(:data) { kml_file.read }

    describe '#features' do
      it 'returns all records' do
        expect(subject.features.count).to eq(2)
      end

      it 'sets the feature name' do
        expect(subject.features).to all(have_attributes :name => be_present)
      end

      it 'sets the feature metadata' do
        expect(subject.features).to all(have_attributes :metadata => be_present)
      end

      it 'sets the feature metadata specifed in extended data' do
        doc = Nokogiri::XML(data)
        doc.css('Placemark').each do |placemark|
          extended_data = doc.create_element('ExtendedData')
          extended_data.add_child doc.create_element('SimpleData', 'value', :name => 'test')
          placemark.add_child(extended_data)
        end

        data.replace doc.to_s

        expect(subject.features).to all(have_attributes :metadata => include('test' => 'value'))
      end

      it 'sets the feature metadata specifed in CDATA double-nested table in the description' do
        doc = Nokogiri::XML(data)
        description = <<-HTML
        <html>
          <body>
            <table>
              <tr>
                <td>A87325</td>
              </tr>
              <tr>
                <td>
                  <table>
                    <tr>
                      <td>test</td>
                      <td>value</td>
                    </tr>
                  </table>
                </td>
              <tr>
            </table>
          </body>
        </html>
        HTML

        doc.css('Placemark').each do |placemark|
          node = doc.create_element('description')
          node.add_child(doc.create_cdata description)
          placemark.add_child(node)
        end

        data.replace doc.to_s

        expect(subject.features).to all(have_attributes :metadata => include('test' => 'value'))
      end

      it 'does not include feature metadata specifed in CDATA double-nested table in the description if there is no value' do
        doc = Nokogiri::XML(data)
        description = <<-HTML
        <html>
          <body>
            <table>
              <tr>
                <td>A87325</td>
              </tr>
              <tr>
                <td>
                  <table>
                    <tr>
                      <td>test</td>
                    </tr>
                  </table>
                </td>
              <tr>
            </table>
          </body>
        </html>
        HTML

        doc.css('Placemark').each do |placemark|
          node = doc.create_element('description')
          node.add_child(doc.create_cdata description)
          placemark.add_child(node)
        end

        data.replace doc.to_s

        expect(subject.features).not_to include(have_attributes :metadata => include('test'))
      end
    end
  end

  context 'when a Placemark holds a MultiGeometry' do
    let(:data) { kml_file_with_multi_geometry_placemarks.read }

    describe '#features' do
      it 'returns one feature per part' do
        expect(subject.features.count).to eq(8)
      end

      it 'names each part after the Placemark holding it' do
        expect(subject.features.map(&:name))
          .to contain_exactly(*['Poly 1'] * 4, *['Poly 2'] * 4)
      end

      it 'gives each part the metadata of the Placemark holding it' do
        expect(subject.features)
          .to all(have_attributes :metadata => include('description' => be_present))
      end

      # Reading a part's Placemark by searching the document, or by asking the part for its
      # ancestors, costs the document's size per part. The document is parsed first, since
      # parsing searches it for NetworkLinks and overlays.
      it 'reads the parts without searching the document again' do
        subject.send(:kml_document)

        expect_any_instance_of(Nokogiri::XML::Document).not_to receive(:search)

        subject.features
      end

      it 'reads a Placemark\'s metadata once however many parts it holds' do
        expect(subject).to receive(:extract_metadata).twice.and_call_original

        subject.features
      end
    end
  end

  context 'when a Placemark holding a MultiGeometry names photos' do
    subject { SpatialFeatures::Importers::KML.new(data, :base_dir => Pathname.new('/base')) }
    let(:data) { kml_file_with_multi_geometry_photos.read }

    describe '#features' do
      it 'returns one feature per part' do
        expect(subject.features.count).to eq(3)
      end

      it 'gives every part the photos the Placemark names' do
        expect(subject.features).to all(have_attributes :importable_image_paths =>
          [Pathname.new('/base/images/two_a.jpg'), Pathname.new('/base/images/two_b.jpg')])
      end

      it 'leaves the image keys out of every part\'s metadata' do
        keys = subject.features.flat_map {|feature| feature.metadata.keys }

        expect(keys & SpatialFeatures::Importers::KML::IMAGE_METADATA_KEYS).to eq([])
      end
    end
  end

  context 'when the input is xml but not kml' do
    let(:data) { "<html><body>hi</body></html>" }

    describe '#features' do
      it 'raises an exception' do
        expect { subject.features }.to raise_exception(SpatialFeatures::ImportError)
      end
    end
  end

  context 'when the input is invalid' do
    let(:data) { "oops" }

    describe '#features' do
      it 'raises an exception' do
        expect { subject.features }.to raise_exception(SpatialFeatures::ImportError)
      end
    end
  end
end
