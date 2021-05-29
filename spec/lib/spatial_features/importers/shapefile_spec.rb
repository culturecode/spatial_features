require 'spec_helper'

describe SpatialFeatures::Importers::Shapefile do
  subject { SpatialFeatures::Importers::Shapefile.new(data) }

  context 'when given a shapefile' do
    let(:data) { shapefile }

    describe '#features' do
      shared_examples_for "a well formed shapefile" do
        it 'returns all records' do
          expect(subject.features.count).to eq(17)
        end

        it 'sets the feature metadata' do
          expect(subject.features).to all(have_attributes :metadata => be_present)
        end

        it 'sets the feature_type' do
          expect(subject.features).to all(have_attributes :feature_type => be_present)
        end
      end

      context 'when the shapefile has all downcased filenames' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile) }

        it_behaves_like "a well formed shapefile"
      end

      context 'when the shapefile has an upcased .shp file' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_with_upcase_shp) }

        it_behaves_like "a well formed shapefile"
      end

      context 'when the shapefile is missing a SHX file' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_without_shape_index) }

        it 'raises an exception' do
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /shapefile_without_shape_index\.shx/)
        end
      end

      context 'when the shapefile is missing a SHP file' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_without_shape_format) }

        it 'raises an exception' do
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /shapefile_without_shape_format\.shp/)
        end
      end

      context 'when the shapefile is missing a DBF file' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_with_missing_dbf_file) }

        it 'raises an exception' do
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /shapefile_with_missing_dbf_file\.dbf/)
        end
      end

      context 'when the shapefile is missing a PRJ file' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_without_projection) }

        it 'raises an exception if there is no default projection' do
          allow(SpatialFeatures::Importers::Shapefile).to receive(:default_proj4_projection).and_return(nil)
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IndeterminateShapefileProjection, /shapefile_without_projection\.prj/)
        end

        it 'is uses the `default_proj4_projection` when no projection can be determined from the shapefile' do
          allow(SpatialFeatures::Importers::Shapefile).to receive(:default_proj4_projection).and_return("+proj=utm +zone=11 +datum=NAD83 +units=m +no_defs")
          expect(subject.features).to be_present
        end
      end
    end

    describe '#cache_key' do
      it 'returns a string' do
        expect(subject.cache_key).to be_a(String)
      end

      it 'changes if the records are different' do

      end
    end
  end
end
