require "test_helper"
require_relative "../../support/accounting_world"

class Accounting::SyncJobsTest < ActiveJob::TestCase
  include AccountingWorld

  setup do
    @gateway = create_quickbooks_gateway
    @fake = fake_quickbooks
  end

  teardown { reset_fake_quickbooks }

  test "nothing runs while the feature is off" do
    with_accounting(false) do
      Accounting::FullSyncJob.perform_now(@gateway)
      Accounting::ChangesJob.perform_now(@gateway)
      Accounting::FetchRecordJob.perform_now(@gateway, "Invoice", "130")

      assert_no_enqueued_jobs do
        Accounting::ScheduleChangesJob.perform_now
        travel_to(Date.new(2026, 11, 29).noon) { Accounting::NightlyJob.perform_now }
      end
    end
    assert_empty @fake.requests
  end

  test "the full sync job copies the records" do
    answer_queries
    with_accounting { Accounting::FullSyncJob.perform_now(@gateway) }

    assert_equal 2, @gateway.accounting_records.where(role: "charge").count
  end

  test "a source that isn't connected isn't synced" do
    gateway = create_quickbooks_gateway(connected: false)
    with_accounting { Accounting::FullSyncJob.perform_now(gateway) }

    assert_empty @fake.requests
  end

  test "every 15 minutes, a changes job for each connected source with a change feed" do
    create_quickbooks_gateway(connected: false)
    with_accounting do
      assert_enqueued_with(job: Accounting::ChangesJob, args: [ @gateway ]) { Accounting::ScheduleChangesJob.perform_now }
      assert_enqueued_jobs 1, only: Accounting::ChangesJob
    end
  end

  test "the schedule queues a changes job only for sources that are due" do
    quiet = create_quickbooks_gateway(change_check: "daily")
    manual = create_quickbooks_gateway(change_check: "manual")
    now = Time.utc(2026, 11, 25, 9, 0)
    @gateway.update!(change_check: "hourly")
    [ @gateway, quiet, manual ].each { |gateway| gateway.record_state!(last_change_check_at: Time.utc(2026, 11, 25, 6, 0)) }

    with_accounting do
      travel_to(now) do
        assert_enqueued_with(job: Accounting::ChangesJob, args: [ @gateway ]) { Accounting::ScheduleChangesJob.perform_now }
        assert_enqueued_jobs 1, only: Accounting::ChangesJob
      end
    end
  end

  test "a source checked only on request skips the weekly read, but the rules are still evaluated" do
    @gateway.update!(change_check: "manual")
    rule = AccountingRule.create!(name: "Dues", kind: "balance", gateway: @gateway, enabled: true)

    with_accounting do
      travel_to(Date.new(2026, 11, 29).noon) do
        assert_no_enqueued_jobs(only: Accounting::FullSyncJob) { Accounting::NightlyJob.perform_now }
        assert_enqueued_with(job: Accounting::EvaluateRuleJob, args: [ rule ])
      end
    end
  end

  test "the nightly job reads everything again on Sundays only" do
    with_accounting do
      travel_to(Date.new(2026, 11, 28).noon) { assert_no_enqueued_jobs { Accounting::NightlyJob.perform_now } }
      travel_to(Date.new(2026, 11, 29).noon) do
        assert_enqueued_with(job: Accounting::FullSyncJob, args: [ @gateway ]) { Accounting::NightlyJob.perform_now }
      end
    end
  end

  test "a failed sync keeps the records, keeps the error and fires sync failed" do
    answer_queries
    with_accounting { Accounting::FullSyncJob.perform_now(@gateway) }
    Hook.create!(name: "Tell the treasurer", event: "accounting - sync failed", code: "model.record_state!(hook_fired: true)")

    reset_fake_quickbooks
    fake_quickbooks.on(:get, "/query", status: 400, body: { "Fault" => { "Error" => [ { "Message" => "Invalid query", "code" => "4000" } ] } })
    with_accounting { Accounting::FullSyncJob.perform_now(Gateway.find(@gateway.id)) }

    @gateway.reload
    assert_match "Invalid query", @gateway.last_error
    assert @gateway.configuration["hook_fired"]
    assert_equal 2, @gateway.accounting_records.current.where(role: "charge").count
  end

  test "rate limits are retried" do
    @fake.on(:get, "/query", status: 429, body: "")

    with_accounting do
      assert_enqueued_with(job: Accounting::FullSyncJob) { Accounting::FullSyncJob.perform_now(@gateway) }
    end
    assert_nil @gateway.reload.last_error
  end

  test "a refused sign-in stops syncing until a reconnect" do
    @gateway.accounting_credential.update!(access_token_expires_at: 1.minute.ago)
    @fake.on(:post, Accounting::Quickbooks::TOKEN_URL, status: 400, body: qbo_fixture("token_refused"))

    with_accounting { Accounting::ChangesJob.perform_now(@gateway) }
    assert_equal "needs_reconnect", @gateway.reload.connection_status

    with_accounting { assert_no_enqueued_jobs { Accounting::ScheduleChangesJob.perform_now } }
  end

  test "the recurring schedule includes the accounting jobs" do
    tasks = GatherPack::RecurringSchedule.tasks
    assert_equal "Accounting::ScheduleChangesJob", tasks[:accounting_changes][:class]
    assert_equal "Accounting::NightlyJob", tasks[:accounting_nightly][:class]
  end
end
