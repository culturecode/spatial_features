require 'base64'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'zip'

# Builds every file in `spec/fixtures`. See `spec/fixtures/README.md` for what the fixtures
# are for and which of their properties the specs depend on.
module FixtureGenerator
  # Projected rather than geographic, so that importing a shapefile exercises reprojection.
  SRS = 'EPSG:26911'.freeze # NAD83 / UTM zone 11N

  # An 8x8 solid, the smallest thing that is still a JPEG. Embedded rather than generated so
  # that building the fixtures needs no image tooling.
  TINY_JPEG = Base64.decode64(<<~B64).freeze
    /9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABQODxIPDRQSEBIXFRQYHjIhHhwcHj0sLiQySUBMS0dA
    RkVQWnNiUFVtVkVGZIhlbXd7gYKBTmCNl4x9lnN+gXz/2wBDARUXFx4aHjshITt8U0ZTfHx8fHx8
    fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHz/wAARCAAIAAgDASIA
    AhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAP/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEB
    AQAAAAAAAAAAAAAAAAAABAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAC8/
    /9k=
  B64

  # An archive holding a symlink entry beside a regular file. Embedded because rubyzip
  # declines to write a symlink entry, so the task cannot build this one from its parts.
  SYMLINK_ARCHIVE = Base64.decode64(<<~B64).freeze
    UEsDBAoAAAAAAAJQEF0KuR8pCwAAAAsAAAAEABwAbGlua1VUCQADlOyBapTsgWp1eAsAAQT1AQAA
    BAAAAAAvZXRjL3Bhc3N3ZFBLAwQKAAAAAAACUBBdAAAAAAAAAAAAAAAABwAcAGxheWVycy9VVAkA
    A5TsgWqU7IFqdXgLAAEE9QEAAAQAAAAAUEsDBAoAAAAAAAJQEF3vi38LEAAAABAAAAAPABwAbGF5
    ZXJzL2RhdGEuc2hwVVQJAAOU7IFqlOyBanV4CwABBPUBAAAEAAAAAHNoYXBlZmlsZSBieXRlcwpQ
    SwECHgMKAAAAAAACUBBdCrkfKQsAAAALAAAABAAYAAAAAAAAAAAA7aEAAAAAbGlua1VUBQADlOyB
    anV4CwABBPUBAAAEAAAAAFBLAQIeAwoAAAAAAAJQEF0AAAAAAAAAAAAAAAAHABgAAAAAAAAAEADt
    QUkAAABsYXllcnMvVVQFAAOU7IFqdXgLAAEE9QEAAAQAAAAAUEsBAh4DCgAAAAAAAlAQXe+LfwsQ
    AAAAEAAAAA8AGAAAAAAAAQAAAKSBigAAAGxheWVycy9kYXRhLnNocFVUBQADlOyBanV4CwABBPUB
    AAAEAAAAAFBLBQYAAAAAAwADAOwAAADjAAAAAAA=
  B64

  class << self
    def build_all(dir)
      FileUtils.mkdir_p(dir)
      Dir.mktmpdir do |work|
        build_shapefiles(dir, work)
        build_documents(dir, work)
      end
    end

    # SHAPEFILES

    def build_shapefiles(dir, work)
      components = write_layer(work, 'polygons', 17)
      complete = components.map { |path| [::File.basename(path), path] }

      write_zip(::File.join(dir, 'shapefile.zip'), complete)

      # Each of these drops exactly one required component.
      %w[prj shx shp dbf].zip(%w[without_projection without_shape_index without_shape_format
                                 with_missing_dbf_file]).each do |ext, name|
        write_zip(::File.join(dir, "shapefile_#{name}.zip"),
                  complete.reject { |entry, _| entry.end_with?(".#{ext}") })
      end

      # An upcased .shp, which the importer finds only because it downcases entry names.
      write_zip(::File.join(dir, 'shapefile_with_upcase_shp.zip'),
                complete.map { |entry, path| entry.end_with?('.shp') ? ['POLYGONS.SHP', path] : [entry, path] })

      # A .shx whose basename does not match the .shp, so the pair cannot be resolved.
      write_zip(::File.join(dir, 'shapefile_with_incorrect_shx_basename.zip'),
                [['shapefile/', :directory]] +
                complete.map do |entry, path|
                  entry.end_with?('.shx') ? ['shapefile/mismatched.shx', path] : ["shapefile/#{entry}", path]
                end)

      # A dot prefixed duplicate beside the real thing, which must be ignored.
      shp = complete.find { |entry, _| entry.end_with?('.shp') }.last
      write_zip(::File.join(dir, 'shapefile_with_dot_prefix.zip'), complete + [['.polygons.shp', shp]])

      # What Finder writes: an AppleDouble sidecar per file, keeping the original extension.
      write_zip(::File.join(dir, 'shapefile_with_macosx_resources.zip'),
                [['shapefile/', :directory]] +
                complete.map { |entry, path| ["shapefile/#{entry}", path] } +
                [['shapefile/.DS_Store', :empty],
                 ['__MACOSX/shapefile/._polygons.shp', :empty],
                 ['__MACOSX/shapefile/._.DS_Store', :empty]])

      # Two layers in one archive, named so the alphabetical pick is unambiguous.
      a = write_layer(work, 'layer_a', 22)
      b = write_layer(work, 'layer_b', 48, :origin_n => 5_600_000)
      write_zip(::File.join(dir, 'archive_with_multiple_shps.zip'),
                (a + b).map { |path| [::File.basename(path), path] })

      # An archive of archives, which the importer unwraps one level to find a shapefile.
      write_zip(::File.join(dir, 'nested_archive_of_shapefiles.zip'),
                [['shapefile.zip', ::File.join(dir, 'shapefile.zip')],
                 ['shapefile_with_upcase_shp.zip', ::File.join(dir, 'shapefile_with_upcase_shp.zip')]])

      # Nothing the importer recognises.
      write_zip(::File.join(dir, 'archive_without_any_known_file.zip'),
                [['notes.whatever', :empty]])

      ::File.binwrite(::File.join(dir, 'archive_with_symlink.zip'), SYMLINK_ARCHIVE)
    end

    # Writes `count` square polygons on a regular grid, in metres, as an ESRI Shapefile.
    # Returns the component paths, in shp/shx/dbf/prj order.
    def write_layer(work, layer, count, origin_e: 500_000, origin_n: 5_500_000, size: 1_000, step: 2_000, cols: 6)
      features = Array.new(count) do |i|
        e = origin_e + (i % cols) * step
        n = origin_n + (i / cols) * step
        { :type => 'Feature',
          :properties => { :name => format('Area %02d', i + 1),
                           :category => %w[alpha beta gamma][i % 3],
                           :value => (i + 1) * 10 },
          :geometry => { :type => 'Polygon',
                         :coordinates => [[[e, n], [e + size, n], [e + size, n + size], [e, n + size], [e, n]]] } }
      end

      geojson = ::File.join(work, "#{layer}.geojson")
      ::File.write(geojson, JSON.generate(:type => 'FeatureCollection', :features => features))

      paths = %w[shp shx dbf prj].map { |ext| ::File.join(work, "#{layer}.#{ext}") }
      paths.each { |path| ::File.delete(path) if ::File.exist?(path) }
      # Argv form, so nothing here is re-parsed by a shell.
      system('ogr2ogr', '-a_srs', SRS, '-nln', layer, paths.first, geojson) ||
        raise("ogr2ogr failed while writing #{layer}")
      ::File.delete(geojson)

      paths
    end

    # KML, KMZ AND GEOJSON

    def build_documents(dir, work)
      write(::File.join(dir, 'test.kml'), document('test.kml', poly_folder))
      write_kmz(::File.join(dir, 'test.kmz'), document('test.kmz', poly_folder))

      # Altitudes in exponent notation, which must parse.
      write(::File.join(dir, 'kml_file_with_altitude.kml'),
            document('test.kml', poly_folder(:altitude => '-5.976855754852295e-05')))

      # Altitudes that are not numbers at all, which must be tolerated rather than fatal.
      write(::File.join(dir, 'kml_file_with_invalid_altitude.kml'),
            document('kml_file_with_invalid_altitude', poly_folder(:altitude => 'isNaN')))

      # Three placemarks, one a LineString with a single vertex, so two survive.
      write(::File.join(dir, 'kml_file_with_invalid_placemark.kml'),
            document('Invalid Placemark Test', folder('Invalid Placemark Test',
              placemark('Point', 'A point', "        <Point><coordinates>10,20</coordinates></Point>\n") +
              placemark('Line', 'A line', line_string('10,20 11,21 12,22')) +
              placemark('Invalid Line', 'A line with one vertex', line_string('10,20')))))

      # Structurally valid and completely empty.
      write(::File.join(dir, 'kml_file_without_features.kml'),
            document('Without Features Test',
                     folder('Without Features Test', "      <open>1</open>\n")))

      # Nothing but remote layers, so nothing imports and a warning is raised.
      write(::File.join(dir, 'kml_file_with_network_link.kml'),
            document('Remote Layers', folder('Remote folder', (1..3).map { |i|
              network_link("Remote Layer #{i}", "https://example.com/layers/#{i}.kml")
            }.join)))

      # A remote layer beside real placemarks: the placemarks still import.
      write(::File.join(dir, 'kml_file_with_network_link_and_features.kml'),
            document('kml_file_with_network_link_and_features.kml',
                     folder('Remote folder', network_link('Remote Layer', 'https://example.com/remote.kmz')) +
                     poly_folder))

      # A raster overlay carries no geometry, so it is reported rather than imported.
      write(::File.join(dir, 'kml_file_with_ground_overlay.kml'),
            document('kml_file_with_ground_overlay.kml', overlay_folder))
      write(::File.join(dir, 'kml_file_with_ground_overlay_and_features.kml'),
            document('kml_file_with_ground_overlay_and_features.kml', overlay_folder + poly_folder))

      # Two Placemarks, each holding several polygons in one MultiGeometry, the shape design
      # software exports when it models an object out of many faces. Each polygon imports as
      # its own feature, taking the name and metadata of the Placemark holding it.
      write(::File.join(dir, 'kml_file_with_multi_geometry_placemarks.kml'),
            document('kml_file_with_multi_geometry_placemarks.kml', multi_geometry_folder))

      # Geometry with no Placemark ancestor, so it imports with no name and no metadata.
      write_kmz(::File.join(dir, 'kmz_file_features_without_placemarks.kmz'),
                document('Geometry Without Placemarks',
                         folder('Geometry folder',
                                "      <MultiGeometry>\n" + polygon(square(10, 20)) +
                                polygon(square(30, 40)) + "      </MultiGeometry>\n")))

      build_images_kmz(::File.join(dir, 'kmz_with_images.kmz'), work)
      build_long_names(::File.join(dir, 'long_placemark_name.kml'))
      build_multiple_kmls(::File.join(dir, 'archive_with_multiple_kmls.zip'), work)

      # A KMZ wrapped in a ZIP, which the importer unwraps one level.
      write_zip(::File.join(dir, 'archive_containing_kmz.zip'),
                [['test.kmz', ::File.join(dir, 'test.kmz')]])

      build_geojson(::File.join(dir, 'geo.json'))
    end

    # Embedded photos referenced from ExtendedData: one placemark with one image, one with
    # two, and one with none.
    def build_images_kmz(target, work)
      images = %w[one.jpg two_a.jpg two_b.jpg].map do |name|
        path = ::File.join(work, name)
        ::File.binwrite(path, TINY_JPEG)
        ["images/#{name}", path]
      end

      schema = <<~SCHEMA
            <Schema id="schema0" name="schema0">
              <SimpleField type="string" name="Description"></SimpleField>
              <SimpleField type="string" name="pdfmaps_photos"><displayName>Photos</displayName></SimpleField>
            </Schema>
      SCHEMA

      placemarks = placemark('Placemark 1', 'One image', photos('one.jpg') + point(10, 20)) +
                   placemark('Placemark 2', 'Two images', photos('two_a.jpg', 'two_b.jpg') + point(12, 22)) +
                   placemark('Placemark 3', 'No images', polygon(square(30, 40)))

      write_kmz(target, document('Image Layer', schema + folder('Layer', placemarks)), images)
    end

    # Names longer than the name column, so the importer has to truncate them.
    def build_long_names(target)
      long = 'Segment description continuing well past the length of the name column so that the ' \
             'importer has to truncate it before the record can be written to the database'
      marks = (1..11).map do |i|
        placemark(i.odd? ? "#{long} (part #{i})" : "Short name #{i}",
                  "<![CDATA[<table><tr><td>Attribute</td><td>Value #{i}</td></tr></table>]]>",
                  "        <MultiGeometry>\n" + polygon(square(10 + i, 20)) + "        </MultiGeometry>\n")
      end.join

      write(target, document('Long Placemark Names', folder('Long Placemark Names', marks)))
    end

    # Two sibling KML files in one archive.
    def build_multiple_kmls(target, work)
      a = document('Sample A', folder('Sample A',
            placemark('Sample A 1', 'First', polygon(square(10, 20))) +
            placemark('Sample A 2', 'Second', polygon(square(30, 40)))))
      b = document('Sample B', folder('Sample B',
            placemark('Sample B 1', 'First', polygon(square(50, 10)))))

      paths = { 'kml_sample_a.kml' => a, 'kml_sample_b.kml' => b }.map do |name, content|
        [name, write(::File.join(work, name), content)]
      end
      write_zip(target, paths)
    end

    # Three features, one of which has no geometry and is skipped.
    def build_geojson(target)
      ring = lambda do |lon, lat|
        [[[lon, lat], [lon + 1, lat], [lon + 1, lat + 1], [lon, lat + 1], [lon, lat]]]
      end
      write(target, JSON.pretty_generate(:type => 'FeatureCollection', :features => [
        { :type => 'Feature', :properties => { :name => 'Feature A', :prop0 => 'value' },
          :geometry => { :type => 'Polygon', :coordinates => ring.call(10, 20) } },
        { :type => 'Feature', :properties => { :name => 'Feature B', :prop0 => 'value' },
          :geometry => { :type => 'Polygon', :coordinates => ring.call(30, 40) } },
        { :type => 'Feature', :properties => { :name => 'Feature C', :prop0 => 'value' },
          :geometry => nil },
      ]) + "\n")
    end

    # KML BUILDING BLOCKS

    def document(name, body)
      %(<?xml version="1.0" encoding="UTF-8"?>\n) +
        %(<kml xmlns="http://www.opengis.net/kml/2.2">\n) +
        "  <Document>\n    <name>#{name}</name>\n#{body}  </Document>\n</kml>\n"
    end

    def folder(name, body)
      "    <Folder>\n      <name>#{name}</name>\n#{body}    </Folder>\n"
    end

    def placemark(name, description, geometry)
      "      <Placemark>\n        <name>#{name}</name>\n" \
      "        <description>#{description}</description>\n#{geometry}      </Placemark>\n"
    end

    # The two named, described polygons that most of the KML fixtures are built around.
    def poly_folder(altitude: nil)
      folder('Poly folder',
             placemark('Poly 1', 'This is a description', polygon(square(10, 20, :altitude => altitude))) +
             placemark('Poly 2', 'This is a description also', polygon(square(30, 40))))
    end

    # The two placemarks of `poly_folder`, each holding `parts` polygons rather than one.
    def multi_geometry_folder(parts: 4)
      placemarks = [['Poly 1', 'This is a description', 10, 20],
                    ['Poly 2', 'This is a description also', 30, 40]]

      folder('Multi geometry folder', placemarks.map { |name, description, lon, lat|
        squares = Array.new(parts) {|i| polygon(square(lon + i, lat, :size => 0.5)) }
        placemark(name, description, "        <MultiGeometry>\n" + squares.join + "        </MultiGeometry>\n")
      }.join)
    end

    def overlay_folder
      folder('Overlay folder',
             "      <GroundOverlay>\n        <name>Basemap Overlay</name>\n" \
             "        <Icon><href>https://example.com/wms?service=wms&amp;request=GetMap</href></Icon>\n" \
             "        <LatLonBox><north>41</north><south>39</south>" \
             "<east>31</east><west>29</west></LatLonBox>\n      </GroundOverlay>\n")
    end

    def network_link(name, href)
      "      <NetworkLink>\n        <name>#{name}</name>\n" \
      "        <Link><href>#{href}</href><viewRefreshMode>onRequest</viewRefreshMode></Link>\n" \
      "      </NetworkLink>\n"
    end

    def photos(*names)
      tags = names.map { |name| %(&lt;img src="images/#{name}"&gt;) }.join
      %(        <ExtendedData><SchemaData schemaUrl="#schema0">\n) +
        %(          <SimpleData name="pdfmaps_photos">#{tags}</SimpleData>\n) +
        %(        </SchemaData></ExtendedData>\n)
    end

    def point(lon, lat)
      "        <Point><coordinates>#{lon},#{lat}</coordinates></Point>\n"
    end

    def line_string(coordinates)
      "        <LineString><coordinates>#{coordinates}</coordinates></LineString>\n"
    end

    def polygon(coordinates)
      "        <Polygon><outerBoundaryIs><LinearRing><coordinates>#{coordinates}" \
      "</coordinates></LinearRing></outerBoundaryIs></Polygon>\n"
    end

    # Returns a closed square ring as a KML coordinate string.
    def square(lon, lat, size: 1, altitude: nil)
      points = [[lon, lat], [lon + size, lat], [lon + size, lat + size], [lon, lat + size], [lon, lat]]
      points.map { |x, y| altitude ? "#{x},#{y},#{altitude}" : "#{x},#{y}" }.join(' ')
    end

    # FILE WRITING

    def write(path, contents)
      ::File.write(path, contents)
      path
    end

    # Writes `entries` - [name, source] pairs - replacing any existing archive. A source of
    # `:directory` or `:empty` writes an entry with no content.
    def write_zip(target, entries)
      ::File.delete(target) if ::File.exist?(target)
      Zip::OutputStream.open(target) do |zos|
        entries.each do |name, source|
          zos.put_next_entry(name)
          zos.write(::File.binread(source)) unless source == :directory || source == :empty
        end
      end
      target
    end

    # A KMZ is a ZIP whose KML entry has to stay named `doc.kml`.
    def write_kmz(target, doc_kml, images = [])
      ::File.delete(target) if ::File.exist?(target)
      Zip::OutputStream.open(target) do |zos|
        zos.put_next_entry('doc.kml')
        zos.write(doc_kml)
        images.each do |name, path|
          zos.put_next_entry(name)
          zos.write(::File.binread(path))
        end
      end
      target
    end
  end
end

namespace :fixtures do
  desc 'Rebuild every file in spec/fixtures from synthetic data'
  task :build do
    dir = ::File.expand_path('../spec/fixtures', __dir__)
    FixtureGenerator.build_all(dir)
    puts "Rebuilt fixtures in #{dir}"
  end
end
