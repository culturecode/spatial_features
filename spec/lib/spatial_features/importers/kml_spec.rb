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
