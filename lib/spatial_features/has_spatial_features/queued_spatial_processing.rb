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
      case spatial_processing_status(:update_features!)
      when :queued, :processing
        true
      else
        false
      end
    end

    def updating_features_failed?
      spatial_processing_status(:update_features!) == :failure
    end

    def spatial_processing_status(method_name)
      if has_attribute?(:spatial_processing_status_cache)
        spatial_processing_status_cache[method_name.to_s]&.to_sym
      end
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

    def spatial_processing_jobs(method_name = nil)
      Delayed::Job.where('queue LIKE ?', "#{spatial_processing_queue_name}#{method_name}%")
    end

    private

    def queue_spatial_task(method_name, *args)
      Delayed::Job.enqueue SpatialProcessingJob.new(self, method_name, *args), :queue => spatial_processing_queue_name + method_name
    end

    def spatial_processing_queue_name
      "#{model_name}/#{id}/"
    end

    # CLASSES

    class SpatialProcessingJob
      def initialize(record, method_name, *args)
        @record = record
        @method_name = method_name
        @args = args
      end

      def enqueue(job)
        update_cached_status(:queued)
      end

      def perform
        update_cached_status(:processing)
        options = @args.extract_options!
        @record.send(@method_name, *@args, **options)
      end

      def success(job)
        update_cached_status(:success)
      end

      def error(job, exception)
        update_cached_status(:failure)
      end

      def failure(job)
        update_cached_status(:failure)
      end

      private

      def update_cached_status(state)
        if @record.has_attribute?(:spatial_processing_status_cache)
          cache = @record.spatial_processing_status_cache || {}
          cache[@method_name] = state
          @record.update_column(:spatial_processing_status_cache, cache)
        end
      end
    end
  end
end
