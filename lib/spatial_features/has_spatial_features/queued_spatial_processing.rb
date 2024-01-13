module SpatialFeatures
  module QueuedSpatialProcessing
    extend ActiveSupport::Concern
    mattr_accessor :priority_offset, default: 0 # Offsets the queued priority of spatial tasks. Lower numbers run with higher priority

    def self.update_cached_status(record, method_name, state)
      return unless record.has_attribute?(:spatial_processing_status_cache)

      cache = record.spatial_processing_status_cache || {}
      cache[method_name] = state
      record.spatial_processing_status_cache = cache
      record.update_column(:spatial_processing_status_cache, cache) if record.will_save_change_to_spatial_processing_status_cache?
    end

    def queue_update_spatial_cache(*args, priority: priority_offset + 1, **kwargs)
      queue_spatial_task('update_spatial_cache', *args, priority:, **kwargs)
    end

    def delay_update_features!(*args, priority: priority_offset + 0, **kwargs)
      queue_spatial_task('update_features!', *args, priority:, **kwargs)
    end

    def updating_features?(**options)
      case spatial_processing_status(:update_features!, **options)
      when :queued, :processing
        true
      else
        false
      end
    end

    def updating_features_failed?
      spatial_processing_status(:update_features!) == :failure
    end

    def spatial_processing_status(method_name, use_cache: true)
      if has_attribute?(:spatial_processing_status_cache)
        update_spatial_processing_status(method_name) unless use_cache
        spatial_processing_status_cache[method_name.to_s]&.to_sym
      end
    end

    def update_spatial_processing_status(method_name)
      latest_job = spatial_processing_jobs(method_name).last

      if !latest_job
        SpatialFeatures::QueuedSpatialProcessing.update_cached_status(self, method_name, nil)
      elsif latest_job.failed_at?
        SpatialFeatures::QueuedSpatialProcessing.update_cached_status(self, method_name, :failure)
      elsif latest_job.locked_at?
        SpatialFeatures::QueuedSpatialProcessing.update_cached_status(self, method_name, :processing)
      else
        SpatialFeatures::QueuedSpatialProcessing.update_cached_status(self, method_name, :queued)
      end
    end

    def feature_update_error
      (failed_feature_update_jobs.first.try(:last_error) || '').split("\n").first
    end

    def running_feature_update_jobs
      spatial_processing_jobs('update_features!').where(failed_at: nil).where.not(locked_at: nil)
    end

    def queued_feature_update_jobs
      spatial_processing_jobs('update_features!').where(failed_at: nil, locked_at: nil)
    end

    def failed_feature_update_jobs
      spatial_processing_jobs('update_features!').where.not(failed_at: nil)
    end

    def spatial_processing_jobs(method_name = nil)
      Delayed::Job.where('queue LIKE ?', "#{spatial_processing_queue_name}#{method_name}%")
    end

    private

    def queue_spatial_task(method_name, *args, priority: 1, **kwargs)
      # NOTE: We pass kwargs as an arg because Delayed::Job does not support separation of positional and keyword arguments in Ruby 3.0. Instead we perform manual extraction in `perform`.
      Delayed::Job.enqueue SpatialProcessingJob.new(self, method_name, *args, kwargs), :queue => spatial_processing_queue_name + method_name, priority:
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

      def before(job)
        ids = running_jobs.where.not(:id => job.id).pluck(:id)
        raise "Already processing delayed jobs in this spatial queue: Delayed::Job #{ids.to_sentence}." if ids.present?
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
        SpatialFeatures::QueuedSpatialProcessing.update_cached_status(@record, @method_name, state)
      end

      def running_jobs
        @record.spatial_processing_jobs
          .where(:locked_at => Delayed::Worker.max_run_time.ago..Time.current)
          .where(:failed_at => nil)
      end
    end
  end
end
