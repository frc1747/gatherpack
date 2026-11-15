require "test_helper"

class GatherPack::RecurringScheduleTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @original_directory = GatherPack::RecurringSchedule.directory
    GatherPack::RecurringSchedule.directory = @dir
  end

  teardown do
    GatherPack::RecurringSchedule.directory = @original_directory
    FileUtils.remove_entry(@dir)
  end

  test "tasks reads every yml file in the directory" do
    write "alpha.yml", <<~YAML
      alpha_job:
        class: GenerateNotificationsJob
        schedule: every hour
    YAML
    write "beta.yml", <<~YAML
      beta_job:
        command: "Rails.logger.info 'hi'"
        schedule: every day
    YAML

    assert_equal %i[alpha_job beta_job], GatherPack::RecurringSchedule.tasks.keys
  end

  test "tasks uses the section for the current environment when present" do
    write "env.yml", <<~YAML
      #{Rails.env}:
        scoped_job:
          class: GenerateNotificationsJob
          schedule: every hour
      other_env:
        other_job:
          class: GenerateNotificationsJob
          schedule: every hour
    YAML

    assert_equal %i[scoped_job], GatherPack::RecurringSchedule.tasks.keys
  end

  test "tasks is empty when the directory has no files" do
    assert_empty GatherPack::RecurringSchedule.tasks
  end

  test "a task defined twice raises" do
    write "a.yml", "dup_job:\n  class: GenerateNotificationsJob\n  schedule: every hour\n"
    write "b.yml", "dup_job:\n  class: GenerateNotificationsJob\n  schedule: every day\n"

    assert_raises(GatherPack::RecurringSchedule::DuplicateTask) { GatherPack::RecurringSchedule.tasks }
  end

  test "a file scoped to another environment adds nothing, even twice" do
    write "a.yml", "other_env:\n  x_job:\n    class: GenerateNotificationsJob\n    schedule: every hour\n"
    write "b.yml", "other_env:\n  x_job:\n    class: GenerateNotificationsJob\n    schedule: every hour\n"

    assert_empty GatherPack::RecurringSchedule.tasks
  end

  test "recurring.yml, as SolidQueue parses it, includes fragment tasks" do
    write "extra.yml", <<~YAML
      extra_job:
        class: GenerateNotificationsJob
        schedule: every 10 minutes
    YAML

    config = parse_recurring_yml

    assert_equal "every 10 minutes", config[:extra_job][:schedule]
    assert_equal "every 5 minutes", config[:generate_notifications_job][:schedule]
  end

  test "a task in recurring.yml wins over a fragment with the same name" do
    write "clash.yml", "generate_notifications_job:\n  class: GenerateNotificationsJob\n  schedule: every day\n"

    assert_equal "every 5 minutes", parse_recurring_yml[:generate_notifications_job][:schedule]
  end

  test "recurring.yml is unchanged when there are no fragments" do
    own_tasks = YAML.safe_load(Rails.root.join("config/recurring.yml").read.gsub(/^<%.*%>$/, "")).deep_symbolize_keys

    assert_includes own_tasks.keys, :generate_notifications_job
    assert_equal own_tasks, parse_recurring_yml
  end

  private

  def parse_recurring_yml
    ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml")).deep_symbolize_keys
  end

  def write(name, content)
    File.write(File.join(@dir, name), content)
  end
end
