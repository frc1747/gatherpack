# Tests for bin/fork-override-check. Needs only git and the standard library,
# not the Rails app or its database:
#
#   ruby test/fork/fork_override_check_test.rb
require "minitest/autorun"
require "fileutils"
require "open3"
require "stringio"
require "tmpdir"

load File.expand_path("../../bin/fork-override-check", __dir__)

class ForkOverrideCheckTest < Minitest::Test
  ORIGINAL = "app/views/devise/sessions/new.html.erb".freeze
  OVERRIDE = "app/view_overrides/modern_skin/devise/sessions/new.html.erb".freeze

  def setup
    @dir = Dir.mktmpdir("fork-override-check")
    @previous = Dir.pwd
    Dir.chdir(@dir)
    @env = %w[ GIT_AUTHOR_NAME GIT_COMMITTER_NAME ].to_h { |key| [ key, "Test" ] }
      .merge(%w[ GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL ].to_h { |key| [ key, "test@example.com" ] })
    @env.each { |key, value| ENV[key] = value }
    git "init", "--quiet"
    write ORIGINAL, "original\n"
    write OVERRIDE, "replacement\n"
    commit "Start"
    @lock = File.join(@dir, "view-overrides.lock")
  end

  def teardown
    Dir.chdir(@previous)
    @env.each_key { |key| ENV.delete(key) }
    FileUtils.remove_entry(@dir)
  end

  def test_maps_an_override_to_its_original
    assert_equal ORIGINAL, ForkOverrideCheck.original_path(OVERRIDE)
    assert_equal "app/views/layouts/_sidebar.html.erb",
      ForkOverrideCheck.original_path("app/view_overrides/my_gatherpack/layouts/_sidebar.html.erb")
  end

  def test_no_overrides_is_not_a_finding
    git "rm", "--quiet", OVERRIDE
    commit "No overrides"
    assert_empty ForkOverrideCheck.findings("HEAD", {})
  end

  def test_an_override_with_no_lock_entry_is_unreviewed
    assert_equal [ :unreviewed ], kinds
  end

  def test_an_accepted_override_is_up_to_date
    ForkOverrideCheck.accept("HEAD", @lock, OVERRIDE)
    assert_empty kinds
  end

  def test_a_changed_original_is_reported_with_its_diff
    ForkOverrideCheck.accept("HEAD", @lock, OVERRIDE)
    write ORIGINAL, "original\nnew upstream line\n"
    commit "Upstream changes the original"

    found = ForkOverrideCheck.findings("HEAD", ForkOverrideCheck.read_lock(@lock))
    assert_equal [ :changed ], found.map { |finding| finding[:kind] }

    out = StringIO.new
    ForkOverrideCheck.report(found, "HEAD", out: out)
    assert_includes out.string, "new upstream line"
    assert_includes out.string, "--accept"
  end

  def test_accepting_clears_a_change
    ForkOverrideCheck.accept("HEAD", @lock, OVERRIDE)
    write ORIGINAL, "changed\n"
    commit "Change"
    ForkOverrideCheck.accept("HEAD", @lock, OVERRIDE)
    assert_empty kinds
  end

  def test_a_change_to_the_override_itself_is_not_a_finding
    ForkOverrideCheck.accept("HEAD", @lock, OVERRIDE)
    write OVERRIDE, "better replacement\n"
    commit "Improve the replacement"
    assert_empty kinds
  end

  def test_an_override_with_no_original_is_reported
    write "app/view_overrides/modern_skin/shared/_new.html.erb", "new\n"
    commit "A new file in the wrong folder"
    ForkOverrideCheck.accept("HEAD", @lock, OVERRIDE)
    assert_equal [ :no_original ], kinds
  end

  def test_a_removed_override_goes_stale_and_accept_drops_it
    ForkOverrideCheck.accept("HEAD", @lock, OVERRIDE)
    git "rm", "--quiet", OVERRIDE
    commit "Remove the override"
    assert_equal [ :stale ], kinds

    ForkOverrideCheck.accept("HEAD", @lock, OVERRIDE)
    assert_empty kinds
    assert_empty ForkOverrideCheck.read_lock(@lock)
  end

  def test_accepting_something_unknown_fails
    assert_raises(ForkOverrideCheck::Error) { ForkOverrideCheck.accept("HEAD", @lock, "app/view_overrides/x/nope.erb") }
  end

  def test_findings_exit_zero_and_a_bad_ref_exits_two
    silently do
      assert_equal 0, ForkOverrideCheck.run([ "--lock", @lock ])
      assert_equal 2, ForkOverrideCheck.run([ "--lock", @lock, "--ref", "no-such-ref" ])
    end
  end

  private

  def kinds
    ForkOverrideCheck.findings("HEAD", ForkOverrideCheck.read_lock(@lock)).map { |finding| finding[:kind] }
  end

  def silently
    out, err = $stdout, $stderr
    $stdout = $stderr = StringIO.new
    yield
  ensure
    $stdout, $stderr = out, err
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def commit(message)
    git "add", "--all"
    git "commit", "--quiet", "--no-verify", "-m", message
  end

  def git(*args)
    _out, err, status = Open3.capture3("git", *args)
    raise err unless status.success?
  end
end
