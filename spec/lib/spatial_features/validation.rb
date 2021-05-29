require 'spec_helper'

describe SpatialFeatures do
  describe '::validate_shapefile_archive!!' do
    let(:data) { shapefile_without_shape_format }

    it 'skips validation with allow_generic_zip_files option' do
      expect { SpatialFeatures::Validation.validate_shapefile_archive!("file.zip", SpatialFeatures::Download.entries(data), allow_generic_zip_files: true) }.not_to raise_exception
    end

    it 'performs validation without allow_generic_zip_files option' do
      expect { SpatialFeatures::Validation.validate_shapefile_archive!("file.zip", SpatialFeatures::Download.entries(data), allow_generic_zip_files: false) }.to \
        raise_exception(SpatialFeatures::Importers::IncompleteShapefileArchive, /file\.shp/)
    end
  end
end
