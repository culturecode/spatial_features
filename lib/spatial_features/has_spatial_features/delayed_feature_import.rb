module SpatialFeatures
  module DelayedFeatureImport
    include FeatureImport

    def queue_feature_update!(options = {})
      job = UpdateFeaturesJob.new(options.merge :spatial_model_type => self.class, :spatial_model_id => self.id)
      Delayed::Job.enqueue(job, :queue => delayed_jobs_queue_name)
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
  end
end
