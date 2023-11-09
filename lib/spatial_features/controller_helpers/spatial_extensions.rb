module SpatialExtensions
  private

  def abstract_refresh_geometry_action(models, **update_options)
    Array.wrap(models).each do |model|
      model.failed_feature_update_jobs.destroy_all
      model.delay_update_features!(**update_options)
    end
  end

  def abstract_proximity_action(scope, target, distance, &block)
    @nearby_records = scope_for_search(scope).within_buffer(target, distance, :distance => true, :intersection_area => true).order('distance_in_meters ASC, intersection_area_in_square_meters DESC, id ASC')
    @target = target

    if block_given?
      block.call(@nearby_records)
    else
      respond_to do |format|
        format.html { render :template => 'shared/spatial/feature_proximity', :layout => false }
        format.kml { render :template => 'shared/spatial/feature_proximity' }
      end
    end
  end

  def abstract_venn_polygons_action(scope, target, &block)
    @venn_polygons = SpatialFeatures.venn_polygons(scope_for_search(scope).intersecting(target), target.class.where(:id => target), :target => target)
    @klass = klass_for_search(scope)
    @target = target

    if block_given?
      block.call(@venn_polygons)
    else
      respond_to do |format|
        format.kml { render :template => 'shared/spatial/feature_venn_polygons' }
      end
    end
  end

  def klass_for_search(scope_or_class)
    scope_or_class.is_a?(ActiveRecord::Relation) ? scope_or_class.klass : scope_or_class
  end

  def scope_for_search(scope)
    if params.key?(:ids)
      ids = params[:ids]
      ids = ids.split(/\D/) if ids.is_a?(String)
      scope.where(:id => ids)
    else
      scope
    end
  end
end
