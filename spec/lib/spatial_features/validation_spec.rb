require 'spec_helper'

describe SpatialFeatures do
  describe '::validate_shapefile_archive!' do
    let(:archive_path) { shapefile_without_shape_format.path }

    it 'skips validation with allow_generic_zip_files option' do
      expect { SpatialFeatures::Validation.validate_shapefile_archive!(archive_path, allow_generic_zip_files: true) }.not_to raise_exception
    end

    it 'performs validation without allow_generic_zip_files option' do
      expect { SpatialFeatures::Validation.validate_shapefile_archive!(archive_path, allow_generic_zip_files: false) }.to \
        raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /missing a SHP file/i)
    end
  end
end
