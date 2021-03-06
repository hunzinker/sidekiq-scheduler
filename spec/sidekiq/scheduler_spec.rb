describe Sidekiq::Scheduler do

  before do
    Sidekiq::Scheduler.enabled = true
    Sidekiq::Scheduler.dynamic = false
    Sidekiq::Scheduler.listened_queues_only = false
    Sidekiq.redis(&:flushall)
    Sidekiq.options[:queues] = Sidekiq::DEFAULTS[:queues]
    Sidekiq::Scheduler.clear_schedule!
    Sidekiq::Scheduler.send(:class_variable_set, :@@scheduled_jobs, {})
    Sidekiq::Worker.clear_all
  end

  it 'sidekiq-scheduler enabled option is working' do
    Sidekiq::Scheduler.enabled = false

    expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to equal(0)

    Sidekiq.schedule = {
      :some_ivar_job => {
        'cron' => '* * * * *',
        'class' => 'SomeIvarJob',
        'args' => '/tmp'
      }
    }

    Sidekiq::Scheduler.load_schedule!

    expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to equal(0)
    expect(Sidekiq::Scheduler.scheduled_jobs).not_to include(:some_ivar_job)
  end

  describe '.enqueue_job' do
    it 'enqueue constantizes' do
      # The job should be loaded, since a missing rails_env means ALL envs.
      ENV['RAILS_ENV'] = 'production'

      config = {
        'cron'  => '* * * * *',
        'class' => 'SomeWorker',
        'queue' => 'high',
        'args'  => '/tmp'
      }

      expect(Sidekiq::Client).to receive(:push).with(process_parameters(config))

      Sidekiq::Scheduler.enqueue_job(config)
    end

    it 'enqueue_job respects queue params' do
      config = {
        'cron' => '* * * * *',
        'class' => 'SystemNotifierWorker',
        'queue' => 'high'
      }

      expect(Sidekiq::Client).to receive(:push).with({
        'cron'  => '* * * * *',
        'class' => SystemNotifierWorker,
        'args'  => [],
        'queue' => 'high'
      })

      Sidekiq::Scheduler.enqueue_job(config)
    end
  end

  describe '.rufus_scheduler' do
    let(:job) { double('job', tags: ['tag'], next_time: 'next_time') }

    it 'can pass options to the Rufus scheduler instance' do
      options = { :lockfile => '/tmp/rufus_lock' }

      expect(Rufus::Scheduler).to receive(:new).with(options)

      Sidekiq::Scheduler.rufus_scheduler_options = options
      Sidekiq::Scheduler.clear_schedule!
    end

    it 'sets a trigger to update the next execution time for the jobs' do
      expect(Sidekiq::Scheduler).to receive(:update_job_next_time)
        .with(job.tags[0], job.next_time)

      Sidekiq::Scheduler.rufus_scheduler.on_post_trigger(job, 'time')
    end
  end

  describe '.load_schedule!' do
    it 'should correctly load the job into rufus_scheduler' do
      expect {
        Sidekiq.schedule = {
          :some_ivar_job => {
            'cron'  => '* * * * *',
            'class' => 'SomeWorker',
            'args'  => '/tmp'
          }
        }

        Sidekiq::Scheduler.load_schedule!
      }.to change { Sidekiq::Scheduler.rufus_scheduler.jobs.size }.from(0).to(1)

      expect(Sidekiq::Scheduler.scheduled_jobs).to include(:some_ivar_job)
    end

    context 'when job has a configured queue' do
      before do
        Sidekiq.schedule = {
          :some_ivar_job => {
            'cron'  => '* * * * *',
            'class' => 'ReportWorker',
            'queue' => 'reporting'
          }
        }
      end

      context 'when listened_queues_only flag is active' do
        before { Sidekiq::Scheduler.listened_queues_only = true }

        context 'when default sidekiq queues' do
          before do
            Sidekiq.options[:queues] = Sidekiq::DEFAULTS[:queues]
          end

          it 'loads the job into the scheduler' do
            Sidekiq::Scheduler.load_schedule!

            expect(Sidekiq::Scheduler.scheduled_jobs).to include(:some_ivar_job)
          end
        end

        context 'when sidekiq queues match job\'s one' do
          before do
            Sidekiq.options[:queues] = ['reporting']
          end

          it 'loads the job into the scheduler' do
            Sidekiq::Scheduler.load_schedule!

            expect(Sidekiq::Scheduler.scheduled_jobs).to include(:some_ivar_job)
          end
        end

        context 'when sidekiq queues does not match job\'s one' do
          before do
            Sidekiq.options[:queues] = ['mailing']
          end

          it 'does not load the job into the scheduler' do
            Sidekiq::Scheduler.load_schedule!

            expect(Sidekiq::Scheduler.scheduled_jobs).to_not include(:some_ivar_job)
          end
        end
      end

      context 'when listened_queues_only flag is inactive' do
        before { Sidekiq::Scheduler.listened_queues_only = false }

        context 'when sidekiq queues does not match job\'s one' do
          before do
            Sidekiq.options[:queues] = ['mailing']
          end

          it 'loads the job into the scheduler' do
            Sidekiq::Scheduler.load_schedule!

            expect(Sidekiq::Scheduler.scheduled_jobs).to include(:some_ivar_job)
          end
        end
      end
    end

    context 'when job has no configured queue' do
      before do
        Sidekiq.schedule = {
          :some_ivar_job => {
            'cron'  => '* * * * *',
            'class' => 'ReportWorker'
          }
        }
      end

      context 'when listened_queues_only flag is active' do
        before { Sidekiq::Scheduler.listened_queues_only = true }

        context 'when configured sidekiq queues' do
          before do
            Sidekiq.options[:queues] = ['mailing']
          end

          it 'does not load the job into the scheduler' do
            Sidekiq::Scheduler.load_schedule!

            expect(Sidekiq::Scheduler.scheduled_jobs).to_not include(:some_ivar_job)
          end
        end

        context 'when default sidekiq queues' do
          before do
            Sidekiq.options[:queues] = Sidekiq::DEFAULTS[:queues]
          end

          it 'loads the job into the scheduler' do
            Sidekiq::Scheduler.load_schedule!

            expect(Sidekiq::Scheduler.scheduled_jobs).to include(:some_ivar_job)
          end
        end
      end

      context 'when listened_queues_only flag is false' do
        before { Sidekiq::Scheduler.listened_queues_only = false }

        context 'when configured sidekiq queues' do
          before do
            Sidekiq.options[:queues] = ['mailing']
          end

          it 'loads the job into the scheduler' do
            Sidekiq::Scheduler.load_schedule!

            expect(Sidekiq::Scheduler.scheduled_jobs).to include(:some_ivar_job)
          end
        end
      end
    end
  end

  describe '.reload_schedule!' do
    it 'should include new values' do
      Sidekiq::Scheduler.dynamic = true

      Sidekiq::Scheduler.load_schedule!

      expect {
        Sidekiq.redis  { |r| r.del(:schedules) }
        Sidekiq.redis do |r|
          r.hset(:schedules, 'some_ivar_job2',
            MultiJson.encode({
                'cron' => '* * * * *',
                'class' => 'SomeWorker',
                'args' => '/tmp/2'
            })
          )
        end

        Sidekiq::Scheduler.reload_schedule!
      }.to change { Sidekiq::Scheduler.scheduled_jobs.include?('some_ivar_job2') }.to(true)
    end

    it 'should remove old values that are not reincluded' do
      Sidekiq::Scheduler.dynamic = true
      Sidekiq.schedule = {
        :some_ivar_job => {
          'cron' => '* * * * *',
          'class' => 'SomeWorker',
          'args' => '/tmp'
        }
      }

      Sidekiq::Scheduler.load_schedule!

      expect {
        Sidekiq.redis  { |r| r.del(:schedules) }

        Sidekiq::Scheduler.reload_schedule!
      }.to change { Sidekiq::Scheduler.scheduled_jobs.include?('some_ivar_job') }.to(false)
    end

    it 'reloads the schedule from redis after 5 seconds when dynamic' do
      Sidekiq.redis { |r| r.flushdb }
      Sidekiq::Scheduler.clear_schedule!

      Sidekiq::Scheduler.dynamic = true
      Sidekiq.set_schedule('some_job', ScheduleFaker.cron_schedule({'args' => '/tmp'}))

      Sidekiq::Scheduler.load_schedule!

      expect {
        Sidekiq.set_schedule('other_job', ScheduleFaker.cron_schedule({'args' => 'sample'}))

        Timecop.travel(7 * 60)
        sleep 0.1
      }.to change { Sidekiq::Scheduler.scheduled_jobs.include?('other_job') }.to(true)
    end
  end

  describe '.load_schedule_job' do

    let(:job_name) { 'some_job' }
    let(:next_time_execution) do
      Sidekiq.redis { |r| r.hexists(Sidekiq::Scheduler.next_times_key, job_name) }
    end

    context 'cron schedule' do
      it 'loads correctly with no options' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.cron_schedule)

        expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to be(1)
        expect(Sidekiq::Scheduler.scheduled_jobs.keys).to eq([job_name])
      end

      it 'stores the next time execution correctly with no options' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.cron_schedule)
        expect(next_time_execution).to be
      end

      it 'sets a tag for the job with the name' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.cron_schedule)

        expect(Sidekiq::Scheduler.scheduled_jobs[job_name].tags).to eq([job_name])
      end

      it 'loads correctly with options' do
        Sidekiq::Scheduler.load_schedule_job(job_name,
          ScheduleFaker.cron_schedule('allow_overlapping' => 'true'))

        expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to be(1)
        expect(Sidekiq::Scheduler.scheduled_jobs.keys).to eq([job_name])
        expect(Sidekiq::Scheduler.scheduled_jobs[job_name].params.keys).
          to include(:allow_overlapping)
      end

      it 'stores the next time execution correctly with options' do
        Sidekiq::Scheduler.load_schedule_job(job_name,
          ScheduleFaker.cron_schedule('allow_overlapping' => 'true'))
        expect(next_time_execution).to be
      end

      it 'does not load the schedule with an empty cron' do
        Sidekiq::Scheduler.load_schedule_job(job_name,
          ScheduleFaker.cron_schedule('cron' => ''))

        expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to be(0)
        expect(Sidekiq::Scheduler.scheduled_jobs.keys).to be_empty
      end

      it 'does not store the next time execution correctly with options' do
        Sidekiq::Scheduler.load_schedule_job(job_name,
          ScheduleFaker.cron_schedule('cron' => ''))

        expect(next_time_execution).not_to be
      end
    end

    context 'every schedule' do
      it 'loads correctly with no options' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.every_schedule)

        expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to be(1)
        expect(Sidekiq::Scheduler.scheduled_jobs.keys).to eq([job_name])
      end

      it 'stores the next time execution correctly with no options' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.every_schedule)
        expect(next_time_execution).to be
      end

      it 'loads correctly with options' do
        Sidekiq::Scheduler.load_schedule_job(job_name,
          ScheduleFaker.every_schedule({'first_in' => '60s'}))

        expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to be(1)
        expect(Sidekiq::Scheduler.scheduled_jobs.keys).to eq([job_name])
        expect(Sidekiq::Scheduler.scheduled_jobs[job_name].params.keys).
          to include(:first_in)
      end

      it 'stores the next time execution correctly with options' do
        Sidekiq::Scheduler.load_schedule_job(job_name,
          ScheduleFaker.every_schedule({'first_in' => '60s'}))
        expect(next_time_execution).to be
      end
    end

    context 'at schedule' do
      it 'loads correctly' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.at_schedule)

        expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to be(1)
        expect(Sidekiq::Scheduler.scheduled_jobs.keys).to eq([job_name])
      end

      it 'stores the next time execution correctly' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.at_schedule)
        expect(next_time_execution).to be
      end
    end

    context 'in schedule' do
      it 'load_schedule_job with in' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.in_schedule)

        expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to be(1)
        expect(Sidekiq::Scheduler.scheduled_jobs.keys).to eq([job_name])
      end

      it 'stores the next time execution correctly' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.in_schedule)
        expect(next_time_execution).to be
      end
    end

    context 'interval schedule' do
      it 'loads correctly' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.interval_schedule)

        expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to be(1)
        expect(Sidekiq::Scheduler.scheduled_jobs.keys).to eq([job_name])
      end

      it 'stores the next time execution correctly' do
        Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.interval_schedule)
        expect(next_time_execution).to be
      end
    end

    it 'does not load without a timing option' do
      Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.invalid_schedule)

      expect(Sidekiq::Scheduler.rufus_scheduler.jobs.size).to be(0)
      expect(Sidekiq::Scheduler.scheduled_jobs.keys).to be_empty
    end

    it 'does not stores the next time execution without a timing option' do
      Sidekiq::Scheduler.load_schedule_job(job_name, ScheduleFaker.invalid_schedule)
      expect(next_time_execution).not_to be
    end
  end

  describe '.idempotent_job_enqueue' do
    def enqueued_jobs_registry
      Sidekiq.redis { |r| r.zrange(pushed_job_key, 0, -1) }
    end

    let(:config) { JobConfigurationsFaker.some_worker }

    let(:job_name) { 'some-worker' }

    let(:pushed_job_key) { Sidekiq::Scheduler.pushed_job_key(job_name) }

    before do
      Sidekiq.redis { |r| r.del(pushed_job_key) }
    end

    let(:time) { Time.now }

    it 'enqueues a job' do
      expect {
        Sidekiq::Scheduler.idempotent_job_enqueue(job_name, time, config)
      }.to change { Sidekiq::Queues[config['queue']].size }.by(1)
    end

    it 'registers the enqueued job' do
      expect {
        Sidekiq::Scheduler.idempotent_job_enqueue(job_name, time, config)
      }.to change { enqueued_jobs_registry.last == time.to_i.to_s }.from(false).to(true)
    end

    context 'when elder enqueued jobs' do
      let(:some_time_ago) { time - Sidekiq::Scheduler::REGISTERED_JOBS_THRESHOLD_IN_SECONDS }

      let(:near_time_ago) { time - Sidekiq::Scheduler::REGISTERED_JOBS_THRESHOLD_IN_SECONDS  / 2 }

      before  do
        Timecop.freeze(some_time_ago) do
          Sidekiq::Scheduler.register_job_instance(job_name, some_time_ago)
        end

        Timecop.freeze(near_time_ago) do
          Sidekiq::Scheduler.register_job_instance(job_name, near_time_ago)
        end
      end

      it 'deregisters elder enqueued jobs' do
        expect {
          Sidekiq::Scheduler.idempotent_job_enqueue(job_name, time, config)
        }.to change { enqueued_jobs_registry.first == some_time_ago.to_i.to_s }.from(true).to(false)
      end
    end

    context 'when the job has been previously enqueued' do
      before { Sidekiq::Scheduler.idempotent_job_enqueue(job_name, time, config) }

      it 'is not enqueued again' do
        expect {
          Sidekiq::Scheduler.idempotent_job_enqueue(job_name, time, config)
        }.to_not change { Sidekiq::Queues[config['queue']].size }
      end
    end

    context 'when it was enqueued for a different Time' do
      before { Sidekiq::Scheduler.idempotent_job_enqueue(job_name, time - 1, config) }

      it 'is enqueued again' do
        expect {
          Sidekiq::Scheduler.idempotent_job_enqueue(job_name, time, config)
        }.to change { Sidekiq::Queues[config['queue']].size }.by(1)
      end
    end
  end

  describe '.update_schedule' do
    it 'loads a new job' do
      Sidekiq::Scheduler.dynamic = true

      Sidekiq.set_schedule('old_job', ScheduleFaker.cron_schedule)
      Sidekiq::Scheduler.load_schedule!

      Sidekiq.set_schedule('new_job', ScheduleFaker.cron_schedule)

      expect {
        Sidekiq::Scheduler.update_schedule
      }.to change { Sidekiq::Scheduler.scheduled_jobs.keys.size }.by(1)

      expect(Sidekiq::Scheduler.scheduled_jobs.keys).to include('new_job')
      expect(Sidekiq.schedule.keys).to include('new_job')
    end

    it 'removes jobs that are removed' do
      Sidekiq::Scheduler.dynamic = true

      Sidekiq.set_schedule('old_job', ScheduleFaker.cron_schedule)
      Sidekiq::Scheduler.load_schedule!

      Sidekiq.remove_schedule('old_job')

      expect {
        Sidekiq::Scheduler.update_schedule
      }.to change { Sidekiq::Scheduler.scheduled_jobs.keys.size }.by(-1)

      expect(Sidekiq::Scheduler.scheduled_jobs.keys).to_not include('old_job')
      expect(Sidekiq.schedule.keys).to_not include('old_job')
    end

    it 'updates already scheduled jobs' do
      Sidekiq::Scheduler.dynamic = true

      Sidekiq.set_schedule('old_job', ScheduleFaker.cron_schedule)
      Sidekiq::Scheduler.load_schedule!

      new_args = {
        'cron'  => '1 * * * *',
        'class' => 'SystemNotifierWorker',
        'args'  => ''
      }

      Sidekiq.set_schedule('old_job', ScheduleFaker.cron_schedule(new_args))

      expect {
        Sidekiq::Scheduler.update_schedule
      }.to_not change { Sidekiq::Scheduler.scheduled_jobs.keys.size }

      expect(Sidekiq::Scheduler.scheduled_jobs.keys).to include('old_job')
      expect(Sidekiq.schedule.keys).to include('old_job')

      job = Sidekiq.schedule['old_job']
      rufus_job = Sidekiq::Scheduler.scheduled_jobs['old_job']

      expect(job).to eq(new_args)
      expect(rufus_job.original).to eq(new_args['cron'])
    end

    it 'removes the changed flag' do
      Sidekiq::Scheduler.dynamic = true

      Sidekiq.set_schedule('old_job', ScheduleFaker.cron_schedule)
      Sidekiq::Scheduler.load_schedule!

      Sidekiq.set_schedule('old_job', ScheduleFaker.cron_schedule('cron' => '1 * * * *'))

      expect {
        Sidekiq::Scheduler.update_schedule
      }.to_not change { Sidekiq::Scheduler.scheduled_jobs.keys.size }

      expect(Sidekiq.redis { |r| r.scard(:schedules_changed) }).to be(0)
    end
  end

  describe '.enque_with_active_job' do
    it 'enque an object with no args' do
      expect(EmailSender).to receive(:new).with(no_args).twice.and_call_original

      Sidekiq::Scheduler.enque_with_active_job({
        'class' => EmailSender,
        'args'  => []
      })
    end

    describe 'enque an object with args' do
      it 'should be correctly enqueued' do
        expect(AddressUpdater).to receive(:new).with(100).
          and_call_original
        expect(AddressUpdater).to receive(:new).with(no_args).
          and_call_original

        Sidekiq::Scheduler.enque_with_active_job({
          'class' => AddressUpdater,
          'args'  => [100]
        })
      end
    end
  end

  describe '.enque_with_sidekiq' do
    let(:config) { JobConfigurationsFaker.some_worker }

    it 'enqueues a job into a sidekiq queue' do
      expect {
        Sidekiq::Scheduler.enque_with_sidekiq(config)
      }.to change { Sidekiq::Queues[config['queue']].size }.by(1)
    end
  end

  describe '.initialize_active_job' do
    describe 'when the object has no arguments' do
      it 'should be correctly initialized' do
        expect(EmailSender).to receive(:new).with(no_args).and_call_original

        object = Sidekiq::Scheduler.initialize_active_job(EmailSender, [])

        expect(object).to be_instance_of(EmailSender)
      end
    end

    describe 'when the object has a hash as an argument' do
      it 'should be correctly initialized' do
        expect(::EmailSender).to receive(:new).with({testing: 'Argument'}).and_call_original

        object = Sidekiq::Scheduler.initialize_active_job(EmailSender, {testing: 'Argument'})

        expect(object).to be_instance_of(EmailSender)
      end
    end

    describe 'when the object has many arguments' do
      it 'should be correctly initialized' do
        expect(EmailSender).to receive(:new).with('one', 'two').and_call_original

        object = Sidekiq::Scheduler.initialize_active_job(EmailSender, ['one', 'two'])

        expect(object).to be_instance_of(EmailSender)
      end
    end
  end

  describe '.register_job_instance' do
    let(:job_name) { 'some-worker' }

    let(:pushed_job_key) { Sidekiq::Scheduler.pushed_job_key(job_name) }

    let(:now) { Time.now }

    it { expect(Sidekiq::Scheduler.register_job_instance(job_name, now)).to be true }

    it 'stores the job instance into Redis' do
      expect {
        Sidekiq::Scheduler.register_job_instance(job_name, now)
      }.to change { Sidekiq.redis { |r| r.zcard(pushed_job_key) } }.by(1)
    end

    it 'persists a expirable key' do
      Sidekiq::Scheduler.register_job_instance(job_name, now)

      Timecop.travel(Sidekiq::Scheduler::REGISTERED_JOBS_THRESHOLD_IN_SECONDS) do
        expect(Sidekiq.redis { |r| r.exists(pushed_job_key) }).to be false
      end
    end

    context 'when job has been previously registered' do
      before { Sidekiq::Scheduler.register_job_instance(job_name, now) }

      it { expect(Sidekiq::Scheduler.register_job_instance(job_name, now)).to be false }

      context 'but with different timestamp' do
        let(:another_timestamp) { now + 1 }

        it 'is true' do
          expect(Sidekiq::Scheduler.register_job_instance(job_name, another_timestamp)).to be true
        end
      end
    end
  end

  describe '.update_job_next_time' do
    let(:job_name) { 'job_name' }
    let(:job_next_time) do
      described_class.redis { |r| r.hget(described_class.next_times_key, job_name) }
    end

    before { described_class.update_job_next_time(job_name, next_time) }

    context 'when the next time is nil' do
      let(:next_time) { nil }

      it 'deletes the job\'s next time from redis' do
        expect(job_next_time).not_to be
      end
    end

    context 'when the next time is present' do
      let(:next_time) { 'next_time' }

      it 'adds the value to redis for the job' do
        expect(job_next_time).to eq(next_time)
      end
    end
  end
end
