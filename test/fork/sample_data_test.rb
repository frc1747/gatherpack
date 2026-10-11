# Tests for the plain-Ruby parts of fork/sample_data/sample_data.rb: the
# manifest, finding each feature's file, and the date helpers. Needs only
# the standard library, not the Rails app or its database:
#
#   ruby test/fork/sample_data_test.rb
#
# Loading the data itself is tested in CI (hbr-check.yml loads it twice into
# a freshly migrated database).
require "minitest/autorun"
require "fileutils"
require "tmpdir"

require_relative "../../fork/sample_data/sample_data"

class SampleDataTest < Minitest::Test
  MANIFEST = <<~TEXT
    # Feature manifest: one branch per line.
    feature/alpha
    feature/beta # depends on alpha
    # feature/gamma

  TEXT

  def setup
    Hbr::SampleData.reset!
  end

  def with_build(files)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "fork/sample_data/features"))
      File.write(File.join(root, "fork/features.txt"), MANIFEST)
      files.each { |path, body| File.write(File.join(root, path), body) }
      yield root
    end
  end

  def test_manifest_branches_skip_comments_and_blank_lines
    assert_equal %w[feature/alpha feature/beta], Hbr::SampleData.manifest_branches(MANIFEST)
  end

  def test_feature_path_drops_the_feature_prefix
    assert_equal "/r/fork/sample_data/features/kiosk-auto-clock-in.rb", Hbr::SampleData.feature_path("/r", "feature/kiosk-auto-clock-in")
  end

  def test_plan_warns_about_a_branch_without_sample_data
    with_build("fork/sample_data/features/alpha.rb" => "") do |root|
      plan = Hbr::SampleData.plan(root)
      assert_equal %w[feature/alpha feature/beta], plan[:branches]
      assert plan[:files]["feature/alpha"]
      assert_nil plan[:files]["feature/beta"]
      assert_equal [ "feature/beta has no sample data in fork/sample_data/features/" ], plan[:warnings]
    end
  end

  def test_plan_needs_the_manifest
    Dir.mktmpdir do |root|
      assert_raises(Hbr::SampleData::Error) { Hbr::SampleData.plan(root) }
    end
  end

  def test_load_layers_registers_base_features_and_people
    files = {
      "fork/sample_data/base.rb" => %(Hbr::SampleData.people "Ada Base"\nHbr::SampleData.base { |s| }),
      "fork/sample_data/features/alpha.rb" => %(Hbr::SampleData.people "Al Pha"\nHbr::SampleData.feature("feature/alpha") { |s| })
    }
    with_build(files) do |root|
      Hbr::SampleData.load_layers(Hbr::SampleData.plan(root))
      assert_equal %w[base feature/alpha], Hbr::SampleData.layers.keys
      assert_equal [ "Ada Base", "Al Pha" ], Hbr::SampleData.known_people
    end
  end

  def test_every_manifest_branch_in_this_build_has_sample_data
    root = File.expand_path("../..", __dir__)
    assert_empty Hbr::SampleData.plan(root)[:warnings]
  end

  # Wednesday 2026-10-14, 10:30.
  def clock
    Hbr::SampleData::Clock.new(Time.new(2026, 10, 14, 10, 30))
  end

  def test_relative_days_and_times
    assert_equal Date.new(2026, 10, 28), clock.date(14)
    assert_equal Time.new(2026, 10, 17, 9, 0), clock.days_from_now(3)
    assert_equal Time.new(2026, 10, 13, 18, 0), clock.days_ago(1, hour: 18)
    assert_equal Time.new(2026, 10, 14, 8, 30), clock.hours_ago(2)
  end

  def test_next_weekday_is_after_today
    assert_equal Time.new(2026, 10, 17, 16, 0), clock.next_weekday(:saturday, hour: 16)
    assert_equal Time.new(2026, 10, 21, 9, 0), clock.next_weekday(:wednesday)
  end

  def test_season_runs_from_last_month_to_the_coming_june
    assert_equal [ Date.new(2026, 9, 1), Date.new(2027, 6, 30) ], clock.season
    spring = Hbr::SampleData::Clock.new(Time.new(2027, 3, 5, 9, 0))
    assert_equal [ Date.new(2027, 2, 1), Date.new(2027, 6, 30) ], spring.season
    january = Hbr::SampleData::Clock.new(Time.new(2027, 1, 20, 9, 0))
    assert_equal [ Date.new(2026, 12, 1), Date.new(2027, 6, 30) ], january.season
  end
end
