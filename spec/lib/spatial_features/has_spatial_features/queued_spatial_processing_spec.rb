require 'spec_helper'

describe SpatialFeatures::QueuedSpatialProcessing do
  let(:klass) { new_dummy_class }

  subject(:record) { klass.create }

  describe '#delay_update_features!', delayed_job: false do
    it 'queues with a priority that puts it before a queued update_spatial_cache job' do
      record.delay_update_features!
      expect { record.queue_update_spatial_cache }
        .to change { Delayed::Job.last.priority }
        .by_at_least 1 # Higher priority value runs with lower priority (go figure)
    end
  end

  describe '#invoke_job' do
    it 'allows a feature update to run when no other job is running for the same record' do
      record.delay_update_features!
      record.delay_update_features!
      expect { Delayed::Job.last.invoke_job }.not_to raise_exception
    end

    it 'allows a feature update to run when a job is running for a different record' do
      klass.create.delay_update_features!
      record.delay_update_features!
      Delayed::Job.first.update(:locked_at => Time.current, :locked_by => 'me')
      expect { Delayed::Job.last.invoke_job }.not_to raise_exception
    end

    it 'allows a feature update to run when a locked job for the same record exists, but has expired, i.e. did not get unlocked correctly' do
      record.delay_update_features!
      record.delay_update_features!
      Delayed::Job.first.update(:locked_at => Time.current - Delayed::Worker.max_run_time, :locked_by => 'me')
      expect { Delayed::Job.last.invoke_job }.not_to raise_exception
    end

    it 'does not allow two feature updates to run simultaneously for the same record' do
      record.delay_update_features!
      record.delay_update_features!
      Delayed::Job.first.update(:locked_at => Time.current, :locked_by => 'me')
      expect { Delayed::Job.last.invoke_job }.to raise_exception(/already processing/i)
    end
  end

  describe '#clear_feature_update_error_status' do
    let(:klass) { new_dummy_class(:spatial_processing_status_cache => :jsonb) }

    it 'clears the cached failure status of a record' do
      SpatialFeatures::QueuedSpatialProcessing.update_cached_status(record, :update_features!, :failure)
      expect { record.clear_feature_update_error_status }
        .to change { record.updating_features_failed? }
        .to false
    end

    it 'does not clear the cached status of a record that has not failed' do
      SpatialFeatures::QueuedSpatialProcessing.update_cached_status(record, :update_features!, :processing)

      expect { record.clear_feature_update_error_status }
        .not_to change { record.updating_features? }
        .from true
    end
  end
end
