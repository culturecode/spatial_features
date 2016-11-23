class UpdateFeaturesJob < Struct.new(:options)
  def perform
    model = options[:spatial_model_type].find(options[:spatial_model_id])

    if model.update_features!
      Array(options[:cache_classes]).each {|klass| SpatialFeatures.cache_record_proximity(model, klass) }
      after_feature_update(model)
    end
  rescue => e
    raise "Can't refresh geometry: #{normalize_message(e.message)}"
  end

  private

  def after_feature_update(model)
    # stub to be overridden
  end

  NUMBER_REGEX = /-?\d+\.\d+/

  def normalize_message(message)
    normalized_messages = []

    if message =~ /invalid KML representation/
      normalized_messages += invalid_kml_reason(message).presence || ["KML importer received invalid geometry."]
    end

    if message =~ /Self-intersection/
      normalized_messages += message.scan(/\[(#{NUMBER_REGEX}) (#{NUMBER_REGEX})\]/).collect do |lng, lat|
        "Self-intersection at #{lng},#{lat}"
      end
    end

    if normalized_messages.many?
      return '<ul><li>' + normalized_messages.join('</li><li>') + '</li></ul>'
    elsif normalized_messages.present?
      normalized_messages.first
    else
      return message
    end
  end

  COORDINATE_REGEX = /<LinearRing><coordinates>\s*((?:#{NUMBER_REGEX},#{NUMBER_REGEX},#{NUMBER_REGEX}\s*)+)<\/coordinates><\/LinearRing>/
  def invalid_kml_reason(message)
    message.scan(COORDINATE_REGEX).collect do |match|
      coords = match[0].remove(/,0\.0+/).split(/\s+/).chunk {|c| c }.map(&:first)

      "Sliver polygon detected at #{coords.first}" if coords.length < 4
    end.compact
  end
end
