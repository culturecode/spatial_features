module SpatialFeatures
  # Splits overlapping features into separate polygons at their areas of overlap, and returns an array of objects
  # with kml for the overlapping area and a list of the record ids whose kml overlapped within that area
  def self.venn_polygons(*scopes)
    options = scopes.extract_options!
    scope = scopes.collect do |scope|
      scope.joins(:features).where('features.feature_type = ?', 'polygon').except(:select).select("features.geom AS the_geom").to_sql
    end.join(' UNION ')

    sql = "
      SELECT scope.id, scope.type, ST_AsKML(venn_polygons.geom) AS kml FROM ST_Dump((
        SELECT ST_Polygonize(the_geom) AS the_geom FROM (

          SELECT ST_Union(the_geom) AS the_geom FROM (

              -- Handle Multigeometry
              SELECT ST_ExteriorRing((ST_DumpRings(the_geom)).geom) AS the_geom
              FROM (#{scope}) AS scope

          ) AS exterior_lines

        ) AS noded_lines
        WHERE NOT ST_IsEmpty(the_geom) -- Ignore empty geometry from ST_Union if there are no polygons because polygonize will explode

      )) AS venn_polygons
    "

    # If we have a target model, throw away all venn_polygons not bounded by the target
    if options[:target]
      sql <<
        "INNER JOIN features
          ON features.spatial_model_type = '#{options[:target].class}' AND features.spatial_model_id = #{options[:target].id} AND ST_Intersects(features.geom, venn_polygons.geom) "
    end

    # Join with the original polygons so we can determine which original polygons each venn polygon came from
    scope = scopes.collect do |scope|
      scope.joins(:features).where('features.feature_type = ?', 'polygon').except(:select).select("#{scope.klass.table_name}.id, features.spatial_model_type AS type, features.geom").to_sql
    end.join(' UNION ')
    sql <<
      "INNER JOIN (#{scope}) AS scope
        ON ST_Covers(scope.geom, ST_PointOnSurface(venn_polygons.geom)) -- Shrink the venn polygons so they don't share edges with the original polygons which could cause varying results due to tiny inaccuracy"

    # Eager load the records for each venn polygon
    eager_load_hash = Hash.new {|hash, key| hash[key] = []}
    polygons = ActiveRecord::Base.connection.select_all(sql)
    polygons.group_by{|row| row['type']}.each do |record_type, rows|
      rows.each do |row|
        eager_load_hash[record_type] << row['id']
      end
    end
    eager_load_hash.each do |record_type, ids|
      eager_load_hash[record_type] = record_type.constantize.find(ids)
    end

    # Instantiate objects to hold the kml and records for each venn polygon
    polygons.group_by{|row| row['kml']}.collect do |kml, rows|
      # Uniq on row id in case a single record had self intersecting multi geometry, which would cause it to appear duplicated on a single venn polygon
      records = rows.uniq{|row| row.values_at('id', 'type') }.collect{|row| eager_load_hash.fetch(row['type']).detect{|record| record.id == row['id'].to_i } }
      OpenStruct.new(:kml => kml, :records => records)
    end
  end
end
