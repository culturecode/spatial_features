module SpatialFeatures
  module QueuedSpatialProcessing
    extend ActiveSupport::Concern

    def queue_update_spatial_cache(*args)
      queue_spatial_task('update_spatial_cache', *args)
    end

    def delay_update_features!(*args)
      queue_spatial_task('update_features!', *args)
    end

    def updating_features?
      running_feature_update_jobs.exists?
    end

    def feature_update_error
      (failed_feature_update_jobs.first.try(:last_error) || '').split("\n").first
    end

    def running_feature_update_jobs
      spatial_processing_jobs('update_features!').where(failed_at: nil)
    end

    def failed_feature_update_jobs
      spatial_processing_jobs('update_features!').where.not(failed_at: nil)
    end

    def spatial_processing_jobs(suffix = nil)
      Delayed::Job.where('queue LIKE ?', "#{spatial_processing_queue_name}#{suffix}%")
    end

    private

    def queue_spatial_task(method_name, *args)
      delay(:queue => spatial_processing_queue_name + method_name).send(method_name, *args)
    end

    def spatial_processing_queue_name
      "#{self.class}/#{self.id}/"
    end
  end
end
