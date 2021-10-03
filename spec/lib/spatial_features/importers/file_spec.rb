require 'spec_helper'

describe SpatialFeatures::Importers::File do
  describe '::new' do
    subject { SpatialFeatures::Importers::File }

    shared_examples_for 'format detection' do
      let(:options) { { :some => 'option' } }

      it 'detects kml file urls' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, options)
        subject.new(kml_file.path, options)
      end

      it 'detects kmz file urls' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, options)
        subject.new(kmz_file.path, options)
      end

      it 'detects zipped shapefile file urls' do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once.with(any_args, options)
        subject.new(shapefile.path, options)
      end

      it 'detects kml files' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, options)
        subject.new(kmz_file, options)
      end

      it 'detects kmz files' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, options)
        subject.new(kmz_file, options)
      end

      it 'detects zipped shape files' do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once.with(any_args, options)
        subject.new(shapefile, options)
      end

      it 'detects zip archive with multiple shapefiles' do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once.with(any_args, options)
        subject.new(archive_with_multiple_shps, options)
      end

      it 'detects zip archive with multiple kml files' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, options)
        subject.new(archive_with_multiple_kmls, options)
      end
    end

    context 'when extensions are lower case' do
      before do
        [kml_file, kmz_file, shapefile].each do |file|
          allow(file).to receive(:path).and_return(file.path.downcase)
        end
      end

      it_behaves_like 'format detection'
    end

    context 'when extensions are upper case' do
      before do
        [kml_file, kmz_file, shapefile].each do |file|
          allow(file).to receive(:path).and_return(file.path.upcase)
        end
      end

      it_behaves_like 'format detection'
    end

    context 'when archive does not include the expected file' do
      it 'raises an exception' do
        expect { subject.new(archive_without_any_known_file) }.to raise_exception(SpatialFeatures::ImportError)
      end
    end

    describe '::create_all' do
      subject { SpatialFeatures::Importers::File }

      it "handles kml file urls" do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once
        subject.create_all(kml_file.path)
      end

      it 'handles zipped shapefile file urls' do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once
        subject.create_all(shapefile.path)
      end

      it "imports multiple shapefiles from a zipped archive" do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).twice
        subject.create_all(archive_with_multiple_shps)
      end

      it "imports multiple shapefiles from a zipped archive" do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).twice
        subject.create_all(archive_with_multiple_kmls)
      end
    end
  end
end
