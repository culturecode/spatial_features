require 'spec_helper'

describe SpatialFeatures do
  describe '::features' do
    it 'returns the features of a class'
    it 'returns the features of a scope'
  end

  describe '#total_intersection_area_in_square_meters' do
    TOLERANCE = 0.000001 # Because calculations are performed using projected geometry, there will be a slight inaccuracy
    new_dummy_class(:name => 'House')
    new_dummy_class(:name => 'Disaster')

    subject { create_record_with_polygon(House, Rectangle.new(1, 1)) }

    it 'can intersect a single record' do
      flood = create_record_with_polygon(Disaster, Rectangle.new(1, 0.5))

      expect(subject.total_intersection_area_in_square_meters(flood))
        .to be_within(TOLERANCE).of(0.5)
    end
  end

  describe "::within_buffer" do
    # Because our numbers are small in these tests, we lower the simplification threshold so it is not drastically
    # reshaping geometry in our tests.
    before { allow(AbstractFeature).to receive(:lowres_simplification).and_return(0) }

    TOLERANCE = 0.000001 # Because calculations are performed using projected geometry, there will be a slight inaccuracy
    new_dummy_class(:name => 'BufferedRecord')
    new_dummy_class(:name => 'Shape')
    new_dummy_class(:name => 'Outlier')

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
      let!(:buffered_record) { create_record_with_polygon(BufferedRecord, Rectangle.new(1, 0.5)) }
      let!(:shape) { create_record_with_polygon(Shape, Rectangle.new(1, 1)) }
      let!(:point) { create_record_with_point(Shape, Point.new(0.5, 0.5)) }
      let!(:outlier) { create_record_with_polygon(Outlier, Rectangle.new(1, 1, :x => 2)) }
      let!(:outlier_point) { create_record_with_point(Outlier, Point.new(2, 2)) }

      it 'returns a ActiveRecord::Relation' do
        expect(Shape.within_buffer(buffered_record, 0, options)).to be_a(ActiveRecord::Relation)
      end

      it 'generates valid SQL and returns no records when the buffered record is new' do
        expect(Shape.within_buffer(BufferedRecord.new, 0, options)).to be_empty
      end

      context 'without a buffer' do
        it 'returns records that intersect spatially with the given record' do
          expect(Shape.within_buffer(buffered_record, 0, options)).to contain_exactly(shape, point)
        end

        it 'does not return records that do not intersect spatially with the given record' do
          expect(Outlier.within_buffer(buffered_record, 0, options)).not_to include(outlier, outlier_point)
        end
      end

      context 'with a buffer' do
        it 'returns records within the buffer distance of the given record' do
          expect(Outlier.within_buffer(shape, 1.5, options)).to include(outlier, outlier_point)
        end

        it 'does not return records outside of the buffer distance of the given record' do
          expect(Outlier.within_buffer(shape, 0.9, options)).not_to include(outlier, outlier_point)
        end

        it 'returns records within the buffer distance of the given record when intersecting the same class' do
          other_outlier = create_record_with_polygon(Outlier, Rectangle.new(1, 1, :x => 2))
          expect(Outlier.within_buffer(other_outlier, 1, options)).to include(outlier)
        end

        it 'returns records within the buffer distance of the given record when intersecting the same class in the other direction' do
          other_outlier = create_record_with_polygon(Outlier, Rectangle.new(1, 1, :x => 2))
          outlier
          expect(Outlier.within_buffer(outlier, 1, options)).to include(other_outlier)
        end

        it 'returns records within the buffer distance of the given record when intersecting a subclass' do
          base_class = new_dummy_class(:type)
          sub_class = new_dummy_class(parent: base_class)

          other_outlier = create_record_with_polygon(sub_class, Rectangle.new(1, 1, :x => 2))
          expect(Outlier.within_buffer(other_outlier, 1, options)).to include(outlier)
        end

        it 'returns records of a subclass within the buffer distance of the given record when intersecting the same class' do
          base_class = new_dummy_class(:type)
          sub_class = new_dummy_class(parent: base_class)

          outlier = create_record_with_polygon(sub_class, Rectangle.new(1, 1, :x => 2))
          other_outlier = create_record_with_polygon(sub_class, Rectangle.new(1, 1, :x => 2))

          expect(sub_class.within_buffer(other_outlier, 1, options)).to include(outlier)
        end
      end

      with_options(:distance => true) do
        it 'includes the minimum distance of each record to the given record as the "distance_in_meters" attribute' do
          expect(Shape.within_buffer(buffered_record, 0, options).first).to have_attribute(:distance_in_meters)
        end

        it 'returns 0 as the distance if the shapes overlap' do
          expect(Shape.within_buffer(buffered_record, 0, options).first.distance_in_meters).to eq(0)
        end

        it 'returns an accurate distance between non-overlapping shapes' do
          overlapping_shape = Shape.within_buffer(outlier, 2, options).first
          expect(overlapping_shape.distance_in_meters).to be_within(TOLERANCE).of(1)
        end
      end

      with_options(:distance => false) do
        it 'does not include distance' do
          expect(Shape.within_buffer(buffered_record, 0, options).first).not_to have_attribute(:distance_in_meters)
        end
      end

      with_options(:intersection_area => true) do
        it 'includes for each record, the area in square meters that is intersected by the given record as the "intersection_area_in_square_meters" attribute' do
          expect(Shape.within_buffer(buffered_record, 0, options).first).to have_attribute(:intersection_area_in_square_meters)
        end

        it 'returns 0 as the overlap if the shapes do not overlap' do
          expect(Shape.within_buffer(outlier, 2, options).first.intersection_area_in_square_meters).to eq(0)
        end

        it 'returns an accurate overlap area in square meters' do
          expect(Shape.within_buffer(buffered_record, 0, options).first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.5)
        end
      end

      with_options(:intersection_area => false) do
        it 'does not include intersection area' do
          expect(Shape.within_buffer(buffered_record, 0, options).first).not_to have_attribute(:intersection_area_in_square_meters)
        end
      end
    end

    shared_examples_for 'buffering a record with overlapping features' do
      let!(:triangle) { create_record_with_polygon(BufferedRecord, Rectangle.new(1, 0.5), Rectangle.new(0.5, 1)) }
      let!(:square) { create_record_with_polygon(Shape, Rectangle.new(1, 1)) }

      with_options({:intersection_area => true}, '#intersection_area') do
        it 'returns the correct value for a single overlapping record' do
          expect(Shape.within_buffer(triangle, 0, options).first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.75)
        end

        it 'returns the correct value for multiple overlapping records' do
          create_record_with_polygon(Shape, Rectangle.new(0.5, 0.5))
          squares = Shape.within_buffer(triangle, 0, options).order(:id)

          expect(squares.first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.75)
          expect(squares.last.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.25)
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
      let(:buffered_scope) do
        BufferedRecord.tap do |klass|
          create_record_with_polygon(klass, Rectangle.new(1, 0.5))
          create_record_with_polygon(klass, Rectangle.new(0.5, 1))
        end
      end

      let!(:shape) { create_record_with_polygon(Shape, Rectangle.new(1, 1)) }
      let!(:outlier) { create_record_with_polygon(Outlier, Rectangle.new(1, 1, :x => 2)) }

      it 'returns the overlapping records' do
        expect(Shape.within_buffer(buffered_scope, 0, options)).to include(shape)
      end

      it 'does not return non-overlapping records' do
        expect(Outlier.within_buffer(buffered_scope, 0, options)).not_to include(outlier)
      end

      it 'returns non-overlapping records within the buffer range' do
        expect(Outlier.within_buffer(buffered_scope, 2, options)).to include(outlier)
      end

      it 'does not duplicate records returned' do
        records = Shape.within_buffer(buffered_scope, 0, options).to_a
        expect { records.uniq }.not_to change { records.length }
      end

      with_options(:intersection_area => true) do
        it 'returns the correct value for a single overlapping record' do
          expect(Shape.within_buffer(buffered_scope, 0, options).first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.75)
        end

        it 'returns the correct value for multiple overlapping records' do
          create_record_with_polygon(Shape, Rectangle.new(0.5, 0.5))
          squares = Shape.within_buffer(buffered_scope, 0, options).order(:id)

          expect(squares.first.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.75)
          expect(squares.last.intersection_area_in_square_meters).to be_within(TOLERANCE).of(0.25)
        end

        it 'returns 0 for non-overlapping records' do
          expect(Outlier.within_buffer(buffered_scope, 2, options).first.intersection_area_in_square_meters).to eq(0)
        end
      end
    end

    shared_examples_for 'calculating the area of a record' do
      it 'returns the correct value for a single feature' do
        record = create_record_with_polygon(Shape, Rectangle.new(1, 1))
        expect(record.features.area(options)).to be_within(TOLERANCE).of(1)
      end

      it 'returns the correct value for multiple non-overlapping features' do
        record = create_record_with_polygon(Shape, Rectangle.new(1, 1), Rectangle.new(1, 1, :x => 2))
        expect(record.features.area(options)).to be_within(TOLERANCE).of(2)
      end

      it 'returns the correct value for multiple overlapping features' do
        record = create_record_with_polygon(Shape, Rectangle.new(1, 1), Rectangle.new(1, 1, :x => 0.5))
        expect(record.features.area(options)).to be_within(TOLERANCE).of(1.5)
      end

      # This test is supposed to ensure that a we're using the same geometry column in all code paths, but current the
      # test shapes are probably too simple to show any difference between simplified and non-simplified geomtry
      it 'returns the same value as the area_in_square_meters method on the Feature class' do
        record = create_record_with_polygon(Shape, Rectangle.new(1, 1), Rectangle.new(1, 1, :x => 0.5))
        expect(record.features.area(options)).to be_within(TOLERANCE).of(Feature.where(:id => record.features).area_in_square_meters)
      end

      it 'returns the uncached value if no cached value is set' do
        record = House.create(:features => [create_polygon(Rectangle.new(1, 1))], :features_area => nil)
        expect(record.features.area(options)).to be_within(TOLERANCE).of(1)
      end

      it 'does not recalculate the cached area after save if it has been set explicitly during save' do
        record = House.new(:features_area => 123)
        expect { record.save }.not_to change { record.features_area }
      end
    end

    shared_examples_for 'counting records' do
      it 'returns the correct count'
    end

    with_options :cache => false do
      it_behaves_like 'buffering a record with a single feature'
      it_behaves_like 'buffering a record with overlapping features'
      it_behaves_like 'buffering a scope with overlapping features'
      it_behaves_like 'calculating the area of a record'
      it_behaves_like 'counting records'
    end

    with_options :cache => true do
      it_behaves_like 'buffering a record with a single feature'
      it_behaves_like 'buffering a record with overlapping features'
      it_behaves_like 'buffering a scope with overlapping features'
      it_behaves_like 'calculating the area of a record'
      it_behaves_like 'counting records'

      describe '::within_buffer' do
        it 'returns an SpatialFeatures::UncachedResult if the cache is stale' do
          house = House.create(:features => [create_polygon(Rectangle.new(1, 1))])
          allow_any_instance_of(SpatialCache).to receive(:stale?).and_return(true)

          expect(House.within_buffer(house, options)).to be_a(SpatialFeatures::UncachedResult)
        end

        it 'returns an SpatialFeatures::UncachedResult if the cache is not present' do
          house = House.create(:features => [create_polygon(Rectangle.new(1, 1))])
          house.spatial_caches.destroy_all

          expect(House.within_buffer(house, options)).to be_a(SpatialFeatures::UncachedResult)
        end

        it 'returns no results when uncached and used as a nested query' do
          House.create(:features => [create_polygon(Rectangle.new(1, 1))])
          house = House.create(:features => [create_polygon(Rectangle.new(1, 1))])
          house.spatial_caches.destroy_all

          expect(House.where(:id => House.within_buffer(house, options))).to be_empty
        end
      end
    end
  end
end
