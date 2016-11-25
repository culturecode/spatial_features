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

      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).with(subject.test_kml, {}).and_call_original
      subject.update_features!
    end

    it 'accepts multiple importers' do
      subject = new_dummy_class(:parent => FeatureImportMock) do
        has_spatial_features :import => { :test_kml => :KMLFile, :test_kmz => :KMLFile }
      end.new

      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).with(subject.test_kml, {}).and_call_original
      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).with(subject.test_kmz, {}).and_call_original
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
  end
end
