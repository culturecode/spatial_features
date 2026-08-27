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

  describe '::retry_failed_feature_updates!', delayed_job: false do
    let(:klass) { new_dummy_class(:spatial_processing_status_cache => :jsonb) }

    def status!(record, state)
      SpatialFeatures::QueuedSpatialProcessing.update_cached_status(record, 'update_features!', state)
    end

    it 'queues a feature update for each record whose last import failed' do
      failed = klass.create.tap {|record| status!(record, 'failure') }

      expect { klass.retry_failed_feature_updates! }
        .to change { failed.spatial_processing_jobs('update_features!').count }
        .by(1)
    end

    it 'ignores records that succeeded, and records never imported at all' do
      klass.create.tap {|record| status!(record, 'success') }
      klass.create # no import attempted, so no key in the cache at all

      expect { klass.retry_failed_feature_updates! }.not_to change { Delayed::Job.count }
    end

    it 'passes options through to the queued job' do
      klass.create.tap {|record| status!(record, 'failure') }

      klass.retry_failed_feature_updates!(:priority => 10)

      expect(Delayed::Job.last.priority).to eq(10)
    end
  end

  describe '#feature_update_warnings' do
    let(:klass) { new_dummy_class(:spatial_processing_status_cache => :jsonb) }

    it 'returns the file and the message apart' do
      record.store_feature_update_warnings([{ 'file' => 'upload.zip', 'message' => 'Skipped 1 map image.' }])

      expect(record.feature_update_warnings)
        .to eq([{ 'file' => 'upload.zip', 'message' => 'Skipped 1 map image.' }])
    end

    # Records imported before the pair was stored hold a single pre-joined string. They keep
    # rendering as written rather than being guessed apart on a colon a filename may contain.
    it 'reads a warning stored as a plain string as the message' do
      SpatialFeatures::QueuedSpatialProcessing.update_cached_status(record, 'update_features!', 'failure')
      cache = record.spatial_processing_status_cache
      cache[SpatialFeatures::QueuedSpatialProcessing::WARNINGS_CACHE_KEY] = ['upload.zip: Skipped 1 map image.']
      record.update_column(:spatial_processing_status_cache, cache)

      expect(record.reload.feature_update_warnings)
        .to eq([{ 'file' => nil, 'message' => 'upload.zip: Skipped 1 map image.' }])
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
