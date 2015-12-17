require 'spec_helper'

describe SpatialFeatures do
  describe "::within_buffer" do
    TOLERANCE = 0.000001 # Because calculations are performed using projected geometry, there will be a slight inaccuracy
    BufferedRecord = new_dummy_class
    Shape = new_dummy_class
    Outlier = new_dummy_class

    let(:options) { Hash.new }

    # Helper method to create a context with the modified buffer options
    def self.with_options(opts, description = nil, &block)
      description = (opts.collect{|k,v| "#{k} => #{v}" } + [description]).compact.join(', ')
      context("with #{description}")do
        before { options.merge!(opts) }
        class_exec(&block)
      end
    end

    shared_examples_for 'buffering a record with a single feature' do
      let!(:triangle) { create_record_with_polygon(BufferedRecord, '0 0, 1 0, 1 1, 0 0') }
      let!(:square) { create_record_with_polygon(Shape, '0 0, 1 0, 1 1, 0 1, 0 0') }
      let!(:outlier) { create_record_with_polygon(Outlier, '0 2,1 2,1 3,0 3,0 2') }

      it 'returns a ActiveRecord::Relation' do
        expect(Shape.within_buffer(triangle, 0, options)).to be_a(ActiveRecord::Relation)
      end

      context 'without a buffer' do
        it 'returns records that intersect spatially with the given record' do
          expect(Shape.within_buffer(triangle, 0, options)).to contain_exactly(square)
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

      with_options(:distance => true) do
        it 'includes the minimum distance of each record to the given record as the "distance_in_meters" attribute' do
          expect(Shape.within_buffer(triangle, 0, options).first).to have_attribute(:distance_in_meters)
        end

        it 'returns 0 as the distance if the shapes overlap' do
          expect(Shape.within_buffer(triangle, 0, options).first.distance_in_meters).to eq(0)
        end

        it 'returns an accurate distance between non-overlapping shapes' do
          overlapping_shape = Shape.within_buffer(outlier, 2, options).first
          expect(overlapping_shape.distance_in_meters).to be_within(TOLERANCE).of(1)
        end
      end

      with_options(:distance => false) do
        it 'does not include distance' do
          expect(Shape.within_buffer(triangle, 0, options).first).not_to have_attribute(:distance_in_meters)
        end
      end

      with_options(:intersection_area => true) do
        it 'includes for each record, the area in square meters that is intersected by the given record as the "intersection_area_in_square_meters" attribute' do
          expect(Shape.within_buffer(triangle, 0, options).first).to have_attribute(:intersection_area_in_square_meters)
        end

        it 'returns 0 as the overlap if the shapes do not overlap' do
          expect(Shape.within_buffer(outlier, 2, options).first.intersection_area_in_square_meters).to eq(0)
        end

        it 'returns an accurate overlap area in square meters' do
          expect(Shape.within_buffer(triangle, 0, options).first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.5)
        end
      end

      with_options(:intersection_area => false) do
        it 'does not include intersection area' do
          expect(Shape.within_buffer(triangle, 0, options).first).not_to have_attribute(:intersection_area_in_square_meters)
        end
      end
    end

    shared_examples_for 'buffering a record with overlapping features' do
      let!(:triangle) { create_record_with_polygon(BufferedRecord, '0 0, 1 0, 1 1, 0 0', '0 0, 1 0, 1 1, 0 0') }
      let!(:square) { create_record_with_polygon(Shape, '0 0, 1 0, 1 1, 0 1, 0 0') }

      with_options({:intersection_area => true}, '#intersection_area') do
        it 'returns the correct value for a single overlapping record' do
          expect(Shape.within_buffer(triangle, 0, options).first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.5)
        end

        it 'returns the correct value for multiple overlapping records' do
          create_record_with_polygon(Shape, '0 0, 0.5 0, 0.5 0.5, 0 0.5, 0 0')
          squares = Shape.within_buffer(triangle, 0, options).order(:id)

          expect(squares.first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.5)
          expect(squares.last.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.125)
        end

        it 'does not duplicate records that overlap multiple features' do
          expect(Shape.within_buffer(triangle, 0, options).length).to eq(1)
        end

        it 'runs fast' do
          expect do
            500.times { Shape.within_buffer(triangle, 0, options).to_a }
          end.to take_less_than(1.5).seconds
        end
      end
    end

    shared_examples_for 'buffering a scope with overlapping features' do
      let(:scope) do
        BufferedRecord.tap do |klass|
          create_record_with_polygon(klass, '0 0, 1 0, 1 1, 0 0')
          create_record_with_polygon(klass, '0 0, 2 0, 2 2, 0 0')
        end
      end

      let!(:square) { create_record_with_polygon(Shape, '0 0, 1 0, 1 1, 0 1, 0 0') }
      let!(:outlier) { create_record_with_polygon(Outlier, '0 4,3 4,3 5,0 5,0 4') }

      it 'returns the overlapping records' do
        expect(Shape.within_buffer(scope, 0, options)).to include(square)
      end

      it 'does not return non-overlapping records' do
        expect(Outlier.within_buffer(scope, 0, options)).not_to include(outlier)
      end

      it 'returns non-overlapping records within the buffer range' do
        expect(Outlier.within_buffer(scope, 2, options)).to include(outlier)
      end

      it 'does not duplicate records returned' do
        records = Shape.within_buffer(scope, 0, options).to_a
        expect { records.uniq }.not_to change { records.length }
      end

      with_options(:intersection_area => true) do
        it 'returns the correct value for a single overlapping record' do
          expect(Shape.within_buffer(scope, 0, options).first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.5)
        end

        it 'returns the correct value for multiple overlapping records' do
          create_record_with_polygon(Shape, '0 0, 0.5 0, 0.5 0.5, 0 0.5, 0 0')
          squares = Shape.within_buffer(scope, 0, options).order(:id)

          expect(squares.first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.5)
          expect(squares.last.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.125)
        end

        it 'returns 0 for non-overlapping records' do
          expect(Outlier.within_buffer(scope, 2, options).first.intersection_area_in_square_meters).to eq(0)
        end
      end
    end

    with_options :cache => false do
      it_behaves_like 'buffering a record with a single feature'
      it_behaves_like 'buffering a record with overlapping features'
      it_behaves_like 'buffering a scope with overlapping features'
    end

    with_options :cache => true do
      it_behaves_like 'buffering a record with a single feature'
      it_behaves_like 'buffering a record with overlapping features'
      it_behaves_like 'buffering a scope with overlapping features'
    end
  end

  describe 'caching' do
    it 'is equivalent to cache all records using cache_record_proximity or cache_proximity'
  end
end
