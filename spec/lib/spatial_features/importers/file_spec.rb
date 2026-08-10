require 'spec_helper'

describe SpatialFeatures::Importers::File do
  describe '::new' do
    subject { SpatialFeatures::Importers::File }

    shared_examples_for 'format detection' do
      let(:options) { { :some => 'option' } }

      it 'detects kml file urls' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, hash_including(options))
        subject.new(kml_file.path, **options)
      end

      it 'detects kmz file urls' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, hash_including(options))
        subject.new(kmz_file.path, **options)
      end

      it 'detects zipped shapefile file urls' do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once.with(any_args, hash_including(options))
        subject.new(shapefile.path, **options)
      end

      it 'detects kml files' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, hash_including(options))
        subject.new(kmz_file, **options)
      end

      it 'detects kmz files' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, hash_including(options))
        subject.new(kmz_file, **options)
      end

      it 'detects zipped shape files' do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once.with(any_args, hash_including(options))
        subject.new(shapefile, **options)
      end

      it 'detects zip archive with multiple shapefiles' do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once.with(any_args, hash_including(options))
        subject.new(archive_with_multiple_shps, **options)
      end

      it 'detects zip archive with multiple kml files' do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once.with(any_args, hash_including(options))
        subject.new(archive_with_multiple_kmls, **options)
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

      it 'names the file types the archive did contain, so the uploader can see what they attached' do
        expect { subject.new(archive_without_any_known_file) }
          .to raise_exception(SpatialFeatures::ImportError, /only 1 WHATEVER file/)
      end
    end
  end

  describe '::create_all' do
    subject { SpatialFeatures::Importers::File }

    context 'when given a kml file url' do
      let(:url) { kml_file.path }

      it "imports each file" do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once
        subject.create_all(url)
      end

      it 'sets different source identifiers for features from each file' do
        importers = subject.create_all(url)
        expect(importers.flat_map(&:features).map(&:source_identifier).uniq)
          .to contain_exactly('test.kml')
      end
    end

    context 'when given a shapefile file url' do
      let(:url) { shapefile.path }

      it "imports each file" do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once
        subject.create_all(url)
      end

      it 'sets different source identifiers for features from each file' do
        importers = subject.create_all(url)
        expect(importers.flat_map(&:features).map(&:source_identifier).uniq)
          .to contain_exactly('shapefile.zip/firstnationreserves.shp')
      end
    end

    context 'when given a zip archive with multiple shapefiles' do
      let(:file) { archive_with_multiple_shps }

      it "imports each file" do
        expect(SpatialFeatures::Importers::Shapefile).to receive(:new).twice
        subject.create_all(file)
      end

      it 'sets different source identifiers for features from each file' do
        importers = subject.create_all(file)
        expect(importers.flat_map(&:features).map(&:source_identifier).uniq)
          .to contain_exactly(
            'archive_with_multiple_shps.zip/crims_alcids_treatyareas.shp',
            'archive_with_multiple_shps.zip/crims_bald_eagles_3n_24june2021.shp'
          )
      end
    end

    # Proponents routinely forward the archive they were emailed — a ZIP holding a ZIP per
    # layer, or a ZIP holding a KMZ — rather than the layer files themselves.
    context 'when given a zip archive containing other archives' do
      it 'unwraps the nested archives and imports each shapefile inside them' do
        importers = subject.create_all(nested_archive_of_shapefiles)
        expect(importers.flat_map(&:features)).to be_present
        expect(importers.count).to eq(2)
      end

      it 'unwraps a KMZ nested inside a zip archive' do
        importers = subject.create_all(archive_containing_kmz)
        expect(importers.flat_map(&:features)).to be_present
      end
    end

    context 'when given a zip archive with multiple kml files' do
      let(:file) { archive_with_multiple_kmls }

      it "imports each file" do
        expect(SpatialFeatures::Importers::KMLFile).to receive(:new).twice
        subject.create_all(file)
      end

      it 'sets different source identifiers for features from each file' do
        importers = subject.create_all(file)
        expect(importers.flat_map(&:features).map(&:source_identifier).uniq)
          .to contain_exactly(
            'archive_with_multiple_kmls.zip/kml_sample_a.kml',
            'archive_with_multiple_kmls.zip/kml_sample_b.kml'
          )
      end
    end
  end
end
