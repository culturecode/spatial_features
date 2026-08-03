module SpatialFeatures
  module QueuedSpatialProcessing
    extend ActiveSupport::Concern
    mattr_accessor :priority_offset, default: 0 # Offsets the queued priority of spatial tasks. Lower numbers run with higher priority

    class_methods do
      # Records whose most recent feature import failed. `->>` yields NULL for a missing
      # key, so a record that has never been imported is not included.
      def with_failed_feature_updates
        where("spatial_processing_status_cache->>'update_features!' = 'failure'")
      end

      # Re-import everything whose last attempt failed. Nothing else retries these, so a
      # record broken by a defect stays broken after the defect is fixed unless something
      # sweeps it up.
      #
      # Queued rather than run inline, so a caller (a deploy migration, a console) doesn't
      # block on reimporting shapefiles, and so `SpatialProcessingJob`'s callbacks maintain
      # `spatial_processing_status_cache` — calling `#update_features!` directly bypasses
      # them and leaves a record flagged as failed even when the retry succeeded.
      def retry_failed_feature_updates!(**options)
        with_failed_feature_updates.find_each do |record|
          record.delay_update_features!(**options)
        end
      end
    end

    def self.update_cached_status(record, method_name, state)
      return unless record.has_attribute?(:spatial_processing_status_cache)

      cache = record.spatial_processing_status_cache
      cache[method_name] = state
      record.spatial_processing_status_cache = cache
      record.update_column(:spatial_processing_status_cache, cache) if record.will_save_change_to_spatial_processing_status_cache?
    end

    def spatial_processing_status_cache
      value = super
      return {} unless value.is_a?(Hash)
      return value
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

    def clear_feature_update_error_status
      with_lock do
        SpatialFeatures::QueuedSpatialProcessing.update_cached_status(self, :update_features!, nil) if updating_features_failed?
      end
    end

    def updating_features_failed?
      spatial_processing_status(:update_features!) == :failure
    end

    # Non-fatal messages from the most recent successful feature import (e.g. parts of
    # the source that were skipped). Stored alongside the status cache so they survive
    # job completion, since successful Delayed::Jobs are deleted and can't be read back.
    WARNINGS_CACHE_KEY = 'feature_update_warnings'.freeze

    def feature_update_warnings
      return [] unless has_attribute?(:spatial_processing_status_cache)
      Array(spatial_processing_status_cache[WARNINGS_CACHE_KEY])
    end

    def store_feature_update_warnings(warnings)
      return unless has_attribute?(:spatial_processing_status_cache)

      cache = spatial_processing_status_cache
      warnings = Array(warnings).reject(&:blank?)
      if warnings.present?
        cache[WARNINGS_CACHE_KEY] = warnings
      else
        cache.delete(WARNINGS_CACHE_KEY)
      end
      self.spatial_processing_status_cache = cache
      update_column(:spatial_processing_status_cache, cache) if persisted? && will_save_change_to_spatial_processing_status_cache?
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

    # Most recent first: a record that has failed more than once must report why the
    # current attempt failed, not whichever row the database happened to return.
    def failed_feature_update_jobs
      spatial_processing_jobs('update_features!').where.not(failed_at: nil).order(failed_at: :desc)
    end

    def spatial_processing_jobs(method_name = nil)
      Delayed::Job.where('queue LIKE ?', "#{spatial_processing_queue_name}#{method_name}%")
    end

    private

    def queue_spatial_task(method_name, *args, priority: 1, **kwargs)
      # NOTE: We pass kwargs as an arg because Delayed::Job does not support separation of positional and keyword arguments in Ruby 3.0. Instead we perform manual extraction in `perform`.
      Delayed::Job.enqueue SpatialProcessingJob.new(self, method_name, *args, kwargs), queue: spatial_processing_queue_name + method_name, priority:
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
        ids = running_jobs.where.not(id: job.id).pluck(:id)
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
          .where(locked_at: Delayed::Worker.max_run_time.ago..Time.current)
          .where(failed_at: nil)
      end
    end
  end
end
