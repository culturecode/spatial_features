require 'spec_helper'

describe SpatialFeatures do
  describe "::within_buffer" do
    TOLERANCE = 0.000001 # Because calculations are performed using projected geometry, there will be a slight inaccuracy
    Triangle = new_dummy_class
    Square = new_dummy_class
    Outlier = new_dummy_class

    let(:options) { Hash.new }

    shared_examples_for 'records with simple features' do
      let!(:triangle) { create_record_with_polygon(Triangle, '0 0, 1 0, 1 1, 0 0') }
      let!(:square) { create_record_with_polygon(Square, '0 0, 1 0, 1 1, 0 1, 0 0') }
      let!(:outlier) { create_record_with_polygon(Outlier, '0 2,1 2,1 3,0 3,0 2') }

      before { SpatialFeatures.cache_proximity(Triangle, Square, Outlier) }

      it 'returns a ActiveRecord::Relation' do
        expect(Square.within_buffer(triangle, 0, options)).to be_a(ActiveRecord::Relation)
      end

      context 'without a buffer' do
        it 'returns records that intersect spatially with the given record' do
          expect(Square.within_buffer(triangle, 0, options)).to contain_exactly(square)
        end

        it 'does not return records that do not intersect spatially with the given record' do
          expect(Outlier.within_buffer(triangle, 0, options)).not_to include(outlier)
        end
      end

      context 'with a buffer' do
        it 'returns records within the buffer distance of the given record' do
          expect(Outlier.within_buffer(square, 1, options)).to include(outlier)
        end

        it 'does not return records outside of the buffer distance of the given record' do
          expect(Outlier.within_buffer(square, 0.9, options)).not_to include(outlier)
        end
      end

      context 'with :distance => true' do
        before { options.merge!(:distance => true) }

        it 'includes the minimum distance of each record to the given record as the "distance_in_meters" attribute' do
          expect(Square.within_buffer(triangle, 0, options).first).to have_attribute(:distance_in_meters)
        end

        it 'returns 0 as the distance if the shapes overlap' do
          expect(Square.within_buffer(triangle, 0, options).first.distance_in_meters).to eq(0)
        end

        it 'returns an accurate distance between non-overlapping shapes' do
          overlapping_shape = Square.within_buffer(outlier, 2, options).first
          expect(overlapping_shape.distance_in_meters).to be_within(TOLERANCE).of(1)
        end
      end

      context 'with :distance => false' do
        before { options.merge!(:distance => false) }

        it 'does not include distance' do
          expect(Square.within_buffer(triangle, 0, options).first).not_to have_attribute(:distance_in_meters)
        end
      end

      context 'with :intersection_area => true' do
        before { options.merge!(:intersection_area => true) }

        it 'includes for each record, the area in square meters that is intersected by the given record as the "intersection_area_in_square_meters" attribute' do
          expect(Square.within_buffer(triangle, 0, options).first).to have_attribute(:intersection_area_in_square_meters)
        end

        it 'returns 0 as the overlap if the shapes do not overlap' do
          expect(Square.within_buffer(outlier, 2, options).first.intersection_area_in_square_meters).to eq(0)
        end

        it 'returns an accurate overlap area in square meters' do
          expect(Square.within_buffer(triangle, 0, options).first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.5)
        end
      end

      context 'with :intersection_area => false' do
        before { options.merge!(:intersection_area => false) }

        it 'does not include intersection area' do
          expect(Square.within_buffer(triangle, 0, options).first).not_to have_attribute(:intersection_area_in_square_meters)
        end
      end
    end

    shared_examples_for 'records with multiple features' do
      let!(:triangle) { create_record_with_polygon(Triangle, '0 0, 1 0, 1 1, 0 0', '0 0, 1 0, 1 1, 0 0') }
      let!(:square) { create_record_with_polygon(Square, '0 0, 1 0, 1 1, 0 1, 0 0') }

      before { SpatialFeatures.cache_proximity(Triangle, Square) }

      describe '#intersection_area' do
        before { options.merge!(:intersection_area => true) }

        it 'returns the correct overlap area when the given record has self-overlapping features' do
          expect(Square.within_buffer(triangle, 0, options).first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.5)
        end

        it 'does not duplicate records that overlap multiple features' do
          expect(Square.within_buffer(triangle, 0, options).length).to eq(1)
        end

        it 'runs fast' do
          expect do
            500.times { Square.within_buffer(triangle, 0, options).to_a }
          end.to take_less_than(1.5).seconds
        end
      end
    end

    context 'without caching' do
      before { options.merge! :cache => false }

      it_behaves_like 'records with simple features'
      it_behaves_like 'records with multiple features'
    end

    context 'with caching' do
      before { options.merge! :cache => true }

      it_behaves_like 'records with simple features'
      it_behaves_like 'records with multiple features'
    end
  end
end
