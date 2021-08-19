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
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /FirstNationReserves\.shx/)
        end
      end

      context 'when the shapefile is missing a SHP file' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_without_shape_format) }

        it 'raises an exception' do
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /missing a SHP file/)
        end
      end

      context 'when the shapefile is missing a DBF file' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_with_missing_dbf_file) }

        it 'raises an exception' do
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /FirstNationReserves\.dbf/)
        end
      end

      context 'when the shapefile has an incorrect component basename' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_with_incorrect_shx_basename) }

        it 'raises an exception' do
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /FirstNationReserves\.shx/)
        end
      end

      context 'when the shapefile is missing a PRJ file' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_without_projection) }

        it 'raises an exception if there is no default projection' do
          allow(SpatialFeatures::Importers::Shapefile).to receive(:default_proj4_projection).and_return(nil)
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IndeterminateShapefileProjection, /FirstNationReserves\.prj/)
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

  context 'when given an archive with multiple shapefiles' do
    let(:data) { archive_with_multiple_shps }
    let(:shapefile_features) { {
      "crims_alcids_treatyareas.shp" => 22,
      "crims_bald_eagles_3n_24june2021.shp" => 48
    } }

    it 'automatically chooses a shapefile' do
      subject = SpatialFeatures::Importers::Shapefile.new(data)
      expect(subject.features).not_to be_empty
    end

    it 'generates features for specific shp_file_name' do
      shapefile_features.each do |shp_file_name, feature_count|

        subject = SpatialFeatures::Importers::Shapefile.new(data, shp_file_name: shp_file_name)
        expect(subject.features.count).to eq(feature_count)
      end
    end
  end
end
