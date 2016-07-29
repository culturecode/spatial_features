require 'spec_helper'

describe SpatialFeatures do
  describe '::features' do
    it 'returns the features of a class'
    it 'returns the features of a scope'
  end

  describe '#total_intersection_area_in_square_meters' do
    TOLERANCE = 0.000001 # Because calculations are performed using projected geometry, there will be a slight inaccuracy
    House = new_dummy_class
    Disaster = new_dummy_class

    subject { create_record_with_polygon(House, Rectangle.new(1, 1)) }

    it 'can intersect a single record' do
      flood = create_record_with_polygon(Disaster, Rectangle.new(1, 0.5))

      expect(subject.total_intersection_area_in_square_meters(flood))
        .to be_within(TOLERANCE).of(0.5)
    end
  end
end
