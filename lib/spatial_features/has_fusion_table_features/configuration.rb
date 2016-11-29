module SpatialFeatures
  module FusionTables
    def self.config
      if block_given?
        yield Configuration
      else
        Configuration
      end
    end

    module Configuration
      mattr_accessor :service_account_credentials
    end
  end
end
