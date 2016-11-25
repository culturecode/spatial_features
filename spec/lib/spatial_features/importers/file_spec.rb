require 'spec_helper'

describe SpatialFeatures::Importers::File do
  describe '::new' do
    subject { SpatialFeatures::Importers::File }

    it 'detects kml file urls' do
      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once
      subject.new(kml_file.path)
    end

    it 'detects kmz file urls' do
      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once
      subject.new(kmz_file.path)
    end

    it 'detects zipped shapefile file urls' do
      expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once
      subject.new(shapefile.path)
    end

    it 'detects kml files' do
      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once
      subject.new(kmz_file)
    end

    it 'detects kmz files' do
      expect(SpatialFeatures::Importers::KMLFile).to receive(:new).once
      subject.new(kmz_file)
    end

    it 'detects zipped shape files' do
      expect(SpatialFeatures::Importers::Shapefile).to receive(:new).once
      subject.new(shapefile)
    end
  end
end
