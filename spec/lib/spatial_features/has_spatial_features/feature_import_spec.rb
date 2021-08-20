require 'spec_helper'

describe SpatialFeatures::FeatureImport do
  FeatureImportMock = new_dummy_class do
    self.abstract_class = true # Ensure rails assigns the correct class to the feature's foreign key
    has_spatial_features

    def test_kml
      "#{__dir__}/../../../../spec/fixtures/test.kml"
    end

    def test_kmz
      "#{__dir__}/../../../../spec/fixtures/test.kmz"
    end
  end

  describe '#update_features!' do
    it 'passes data to importers as specified in spatial_features_options[:import]' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_kml => :KMLFile }
      end.new

      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).with(subject.test_kml, be_a(Hash)).and_call_original
      subject.update_features!
    end

    it 'accepts multiple importers' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_kml => :KMLFile, :test_kmz => :KMLFile }
      end.new

      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).with(subject.test_kml, be_a(Hash)).and_call_original
      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).with(subject.test_kmz, be_a(Hash)).and_call_original
      subject.update_features!
    end

    it 'aggregates features if multiple importers are specified' do
      single = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_kml => :KMLFile }
      end.new

      double = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_kml => :KMLFile, 'test_kml' => :KMLFile }
      end.new

      single.update_features!
      double.update_features!
      expect(double.features.count).to eq(single.features.count * 2)
    end

    it 'accepts multiple sources within a single importer' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_files => :KMLFile }

        def test_files
          [test_kml, test_kmz]
        end
      end.new

      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).with(subject.test_kml, be_a(Hash)).and_call_original
      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).with(subject.test_kmz, be_a(Hash)).and_call_original
      subject.update_features!
    end

    it 'passes single shapefile from the zipped archive to the shapefile importer' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_files => :File }

        def test_files
          [shapefile]
        end
      end.new

      expect(SpatialFeatures::Importers::File).to receive(:create_all).once.and_call_original
      expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once.and_call_original
      subject.update_features!
    end

    it 'passes multiple shapefiles from the zipped archive to the shapefile importer' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_files => :File }

        def test_files
          [archive_with_multiple_shps]
        end
      end.new

      expect(SpatialFeatures::Importers::File).to receive(:create_all).once.and_call_original
      expect(SpatialFeatures::Importers::Shapefile).to receive(:new).twice.and_call_original
      subject.update_features!
    end

    it 'passes multiple kmls from the zipped archive to the kml importer' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_files => :File }

        def test_files
          [archive_with_multiple_kmls]
        end
      end.new

      expect(SpatialFeatures::Importers::File).to receive(:create_all).once.and_call_original
      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).twice.and_call_original
      subject.update_features!
    end

    it 'passes the zipped archive to the shapefile importer' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_files => :File }

        def test_files
          [shapefile_archive_path]
        end

        def shapefile_archive_path
          shapefile.path
        end
      end.new

      expect(SpatialFeatures::Importers::File).to receive(:new).with(subject.shapefile_archive_path, be_a(Hash)).and_call_original
      expect(SpatialFeatures::Importers::Shapefile).to receive(:new).with(subject.shapefile_archive_path, be_a(Hash)).and_call_original
      subject.update_features!
    end


    it 'aggregates features if multiple sources are specified within a single importer' do
      single = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_kml => :KMLFile }
      end.new

      double = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_files => :KMLFile }

        def test_files
          [test_kml, test_kml]
        end
      end.new

      single.update_features!
      double.update_features!
      expect(double.features.count).to eq(single.features.count * 2)
    end

    it 'ignores empty source values' do
      subject = new_dummy_class do
        has_spatial_features :import => { :empty_string => :KMLFile }

        def empty_string
          ""
        end
      end.new

      expect(SpatialFeatures::Importers::KMLFile).not_to receive(:new)
      subject.update_features!
    end

    it 'combines the cache key from each importer'

    it 'returns true if features are updated' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_kml => :KMLFile }
      end.new

      expect(subject.update_features!).to be_truthy
    end

    it 'returns nil if features are unchanged' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_kml => :KMLFile }
      end.new

      subject.update_features!
      expect(subject.update_features!).to be_nil
    end

    it 'does not save the spatial model if it is a new record' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_kml => :KMLFile }
      end.new

      expect { subject.update_features! }.not_to change { subject.class.count }
    end

    describe 'spatial caching' do
      let(:other_class) { new_dummy_class }
      subject do
        other_class_name = other_class.name
        new_dummy_class(:parent => FeatureImportMock) do
          has_spatial_features :import => { :test_kml => :KMLFile }, :spatial_cache => other_class_name
        end.create
      end

      it 'updates the spatial cache of the record when the :spatial_cache option is set' do
        expect { subject.update_features! }.to change { subject.spatial_caches.between(subject, other_class).count }.by(1)
      end

      it 'allows spatial caching to be cancelled at run time' do
        expect { subject.update_features!(:spatial_cache => false) }.not_to change { subject.spatial_caches.between(subject, other_class).count }
      end

      it 'allows spatial caching to be run asynchronously at run time' do
        expect { subject.update_features!(:queue_spatial_cache => true) }.to change { subject.spatial_processing_jobs.count }.by(1)
      end

      it 'allows spatial caching to be synchronously at run time' do
        expect { subject.update_features!(:queue_spatial_cache => false) }.not_to change { subject.spatial_processing_jobs.count }
      end
    end
  end
end
