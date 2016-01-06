module ArcGISKmzFeatures
  require 'open-uri'
  require 'digest/md5'

  def update_features!(options = {})
    @skip_invalid = options[:skip_invalid]
    @make_valid = options[:make_valid]
    @feature_error_messages = []
    kml_array = []
    cache_kml = ''

    Array(arcgis_kmz_url).each do |url|
      kml_array << open_kmz_url(url)
      cache_kml << kml_array.last.to_s
    end

    if has_spatial_features_hash?
      new_features_hash = Digest::MD5.hexdigest(cache_kml) if cache_kml.present?

      if new_features_hash != self.features_hash
        replace_features(kml_array)
        update_attributes(:features_hash => new_features_hash)
      else
        return false
      end
    else
      replace_features(kml_array)
    end

    return true
  end

  def queue_feature_update!(options = {})
    Delayed::Job.enqueue ArcGISUpdateFeaturesJob.new(options.merge :spatial_model_type => self.class, :spatial_model_id => self.id), :queue => delayed_jobs_queue_name
  end

  def updating_features?
    running_feature_update_jobs.exists?
  end

  def feature_update_error
    (failed_feature_update_jobs.first.try(:last_error) || '').split("\n").first
  end

  def running_feature_update_jobs
    feature_update_jobs.where(failed_at: nil)
  end

  def failed_feature_update_jobs
    feature_update_jobs.where.not(failed_at: nil)
  end

  def feature_update_jobs
    Delayed::Job.where(queue: delayed_jobs_queue_name)
  end

  private

  def delayed_jobs_queue_name
    "#{self.class}/#{self.id}/update_features"
  end

  def replace_features(kml_array)
    new_features = []
    kml_array.each {|kml| new_features.concat build_features(kml) }

    ActiveRecord::Base.transaction do
      self.features.destroy_all
      new_features.each(&:save)
      self.clear_association_cache # clear_association_cache so after_feature_update knows about the new features

      @feature_error_messages.concat new_features.collect {|feature| "Feature #{feature.name}: #{feature.errors.full_messages.to_sentence}" if feature.errors.present? }.compact.flatten
      if @feature_error_messages.present? && !@skip_invalid
        raise UpdateError, "Error updating #{self.class} #{self.id}. #{@feature_error_messages.to_sentence}"
      end
    end
  end

  def build_features(kml)
    new_type_features = []

    extract_kml_features(kml) do |feature_type, feature, name, metadata|
      begin
        new_type_features << build_feature(feature_type, name, metadata, build_geom(feature))
      rescue => e
        @feature_error_messages << e.message
      end
    end

    return new_type_features
  end

  # Use ST_Force_2D to discard z-coordinates that cause failures later in the process
  def build_geom(feature)
    if make_valid?
      geom = ActiveRecord::Base.connection.select_value("SELECT ST_CollectionExtract(ST_MakeValid(ST_Force_2D(ST_GeomFromKML('#{feature}'))),3)")
    else
      geom = ActiveRecord::Base.connection.select_value("SELECT ST_Force_2D(ST_GeomFromKML('#{feature}'))")
    end
  end

  def extract_kml_features(kml, &block)
    Nokogiri::XML(kml).css('Placemark').each do |placemark|
      name = placemark.css('name').text
      metadata = Hash[Nokogiri::XML(placemark.css('description').text).css('td').collect(&:text).each_slice(2).to_a]

      {'Polygon' => 'POLYGON', 'LineString' => 'LINE', 'Point' => 'POINT'}.each do |kml_type, sql_type|
        placemark.css(kml_type).each do |feature|
          yield sql_type, feature, name, metadata
        end
      end
    end
  end

  def build_feature(feature_type, name, metadata, geom)
    Feature.new(:spatial_model => self, :name => name, :metadata => metadata, :feature_type => feature_type, :geog => geom)
  end

  def open_kmz_url(url)
    url = URI(url)

    Zip::InputStream.open(open(url)) do |io|
      while (entry = io.get_next_entry)
        return io.read if entry.name.downcase == 'doc.kml'
      end
    end

    return nil

  rescue SocketError, Errno::ECONNREFUSED
    raise UpdateError, "ArcGIS Server is not responding. Ensure ArcGIS Server is running and accessible at #{[url.scheme, "//#{url.host}", url.port].select(&:present?).join(':')}."
  rescue OpenURI::HTTPError
    raise UpdateError, "ArcGIS Map Service not found. Ensure ArcGIS Server is running and accessible at #{url}."
  rescue => e
    raise UpdateError, e.message
  end

  # Can be overridden to use PostGIS to force geometry to be valid
  def make_valid?
    !!@make_valid
  end

  class UpdateError < StandardError; end
end
