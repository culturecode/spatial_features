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
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /FirstNationReserves\.shx/i)
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

        it 'does not raise an exception' do # OGR2OGR should build missing file this if it is able to process the shapefile
          expect { subject.features }.not_to raise_exception
        end
      end

      context 'when the shapefile has an incorrect component basename' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_with_incorrect_shx_basename) }

        it 'raises an exception' do
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /FirstNationReserves\.shx/i)
        end
      end

      context 'when the shapefile is missing a PRJ file' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_without_projection) }

        it 'raises an exception if there is no default projection' do
          allow(SpatialFeatures::Importers::Shapefile).to receive(:default_proj4_projection).and_return(nil)
          expect { subject.features }.to raise_exception(SpatialFeatures::Importers::IndeterminateShapefileProjection, /FirstNationReserves\.prj/i)
        end

        it 'uses the `default_proj4_projection` when no projection can be determined from the shapefile' do
          allow(SpatialFeatures::Importers::Shapefile).to receive(:default_proj4_projection).and_return("+proj=utm +zone=11 +datum=NAD83 +units=m +no_defs")
          expect(subject.features).to be_present
        end
      end

      context 'when the shapefile contains a __macosx folder' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_with_macosx_resources) }

        it_behaves_like "a well formed shapefile"

        it 'does not return files inside the __macosx folder' do
          possible_shp_files = subject.send(:possible_shp_files)
          expect(possible_shp_files.select { |file| file.path.include?('__macosx') }).to be_empty
          expect(possible_shp_files.length).to eq(1)
        end
      end

      context 'when the shapefile contains files with dot prefixes' do
        let(:subject) { SpatialFeatures::Importers::Shapefile.new(shapefile_with_dot_prefix) }

        it_behaves_like "a well formed shapefile"

        it 'does not return files prefixed by periods' do
          possible_shp_files = subject.send(:possible_shp_files)
          expect(possible_shp_files.select { |file| file.path.start_with?('.') }).to be_empty
          expect(possible_shp_files.length).to eq(1)
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

    describe '#create_all' do
      let(:subject) { SpatialFeatures::Importers::Shapefile.create_all(shapefile) }

      it 'creates a single importer' do
        expect(subject.count).to eq(1)
        expect(subject.first.features.count).to eq(17)
      end
    end
  end

  context 'when given a zip archive with multiple shapefiles' do
    let(:data) { archive_with_multiple_shps }
    let(:shapefile_features) { {
      "crims_alcids_treatyareas.shp" => 22,
      "crims_bald_eagles_3n_24june2021.shp" => 48
    } }

    describe '#new' do
      it 'automatically selects the first alphabetical SHP file from the archive' do
        subject = SpatialFeatures::Importers::Shapefile.new(data)
        expect(subject.features.count).to eq(22)
      end
    end

    describe '#create_all' do
      it 'creates multiple shapefile importers' do
        importers = SpatialFeatures::Importers::Shapefile.create_all(data)
        expect(importers.count).to eq(2)

        expect(importers[0].features.count).to eq(shapefile_features["crims_alcids_treatyareas.shp"])
        expect(importers[1].features.count).to eq(shapefile_features["crims_bald_eagles_3n_24june2021.shp"])
      end
    end
  end
end
