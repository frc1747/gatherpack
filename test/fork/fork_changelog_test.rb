# Tests for bin/fork-changelog. Needs only git and the standard library, not
# the Rails app or its database:
#
#   ruby test/fork/fork_changelog_test.rb
require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"

load File.expand_path("../../bin/fork-changelog", __dir__)

class ForkChangelogTest < Minitest::Test
  GIT_ENV = {
    "GIT_AUTHOR_NAME" => "Test",
    "GIT_AUTHOR_EMAIL" => "test@example.com",
    "GIT_COMMITTER_NAME" => "Test",
    "GIT_COMMITTER_EMAIL" => "test@example.com",
    "GIT_CONFIG_GLOBAL" => File::NULL,
    "GIT_CONFIG_NOSYSTEM" => "1"
  }.freeze

  MANIFEST = <<~TEXT
    # Feature manifest: one branch per line.
    feature/alpha
    feature/beta # depends on alpha
    # feature/gamma
    # feature/delta # waits on #530
  TEXT

  CATALOG = <<~YAML
    feature/alpha:
      title: Alpha screens
      emoji: "🅰️"
      description: People see alpha.
      audience: Everyone
      settings:
        - name: Alpha
          key: feature_alpha
          default: "off"
  YAML

  REGISTER = <<~MD
    # Status

    | Branch | Status | Shipped | Upstream link | Depends on | Flag | Notes |
    |---|---|---|---|---|---|---|
    | `feature/alpha` | proposed | hbr.1 | PR [#1](https://example.com/1) | — | `feature_alpha` | Notes with a \\| pipe. |
    | `feature/beta` | wip | — | — | `feature/alpha` | — | — |
    | `feature/old` | retired | hbr.1 | PR [#2](https://example.com/2) | — | — | Gone. |
  MD

  def setup
    @dir = Dir.mktmpdir("fork-changelog")
    @time = 1_700_000_000
    git "init", "--quiet", "--initial-branch=upstream-main"
    commit "README.md", "upstream\n", "Initial upstream commit"

    git "checkout", "--quiet", "-b", "hbr/platform"
    write "fork/features.txt", MANIFEST
    write "fork/catalog.yml", CATALOG
    write "FORK.md", REGISTER
    commit_all "Add fork tooling"

    git "checkout", "--quiet", "-b", "feature/alpha", "upstream-main"
    commit "db/migrate/20260101000000_create_alphas.rb", "# alpha\n", "Add alpha"
    git "checkout", "--quiet", "-b", "feature/old", "upstream-main"
    commit "old.txt", "old\n", "Add old"

    # Release 1: alpha and old.
    integrate "feature/alpha", "feature/old"
    git "tag", "-a", "v1.0.0-hbr.1", "-m", "Release 1"

    # Upstream moves on, alpha is rebased onto it and gains a commit, and beta
    # (which needs alpha) replaces old.
    git "checkout", "--quiet", "upstream-main"
    commit "upstream.txt", "more\n", "Upstream change"
    alpha_commit = git("rev-parse", "feature/alpha").strip
    git "checkout", "--quiet", "-B", "feature/alpha", "upstream-main"
    git "cherry-pick", alpha_commit
    commit "alpha.txt", "alpha 2\n", "Change alpha"
    git "checkout", "--quiet", "-b", "feature/beta"
    commit "beta.txt", "beta\n", "Add beta"

    integrate "feature/alpha", "feature/beta"
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_parses_active_and_disabled_manifest_lines
    entries = ForkChangelog.parse_manifest(MANIFEST)

    assert_equal [ [ "feature/alpha", true ], [ "feature/beta", true ], [ "feature/gamma", false ], [ "feature/delta", false ] ],
      entries.map { |entry| [ entry.branch, entry.active ] }
  end

  def test_parses_register_rows_and_dependencies
    register = ForkChangelog.parse_register(REGISTER)

    assert_equal %w[feature/alpha feature/beta feature/old], register.keys
    assert_equal "Notes with a \\| pipe.", register["feature/alpha"]["notes"]
    assert_equal [ "feature/alpha" ], ForkChangelog.dependencies(register["feature/beta"])
    assert_empty ForkChangelog.dependencies(register["feature/alpha"])
  end

  def test_missing_catalog_entry_falls_back_to_branch_name_with_warning
    text, warnings = generate

    assert_includes text, "### ❔ feature/beta"
    assert_includes text, "No description yet. Add `feature/beta` to `fork/catalog.yml`"
    assert_includes warnings, "feature/beta has no entry in fork/catalog.yml"
    assert_includes text, "### 🅰️ Alpha screens"
    assert_includes text, "Alpha (`feature_alpha`): default off"
  end

  def test_disabled_manifest_line_and_retired_rows
    text, = generate
    disabled = text[/## 💤 Disabled and retired.*/m]

    assert_includes disabled, "- `feature/gamma`"
    assert_includes disabled, "- `feature/delta`"
    assert_includes disabled, "| `feature/old` | hbr.1 | PR [#2](https://example.com/2) |"
    refute_includes text, "f3[" # only the two active features are drawn
  end

  def test_diagram_draws_merge_order_and_dependency_edges
    text, = generate
    diagram = text[/```mermaid\n(.*?)```/m, 1]

    assert_includes diagram, "upstream --> platform\n  platform --> f1\n  f1 --> f2"
    assert_includes diagram, %(f2["❔ feature/beta<br/>feature/beta"])
    assert_includes diagram, "f2 -. needs .-> f1"
  end

  def test_groups_new_commits_since_the_last_release_tag
    text, = generate
    news = text[/## 🆕 What's new since v1\.0\.0-hbr\.1.*?(?=<a id="disabled">)/m]

    assert_includes text, "`v1.0.0-hbr.2` when tagged"
    assert_includes news, "### 🅰️ Alpha screens · ✏️ 1 change\n\n- Change alpha"
    refute_includes news, "Add alpha" # rebased, so already released
    assert_includes news, "### ❔ feature/beta · 🆕 new in this build\n\n- Add beta"
    assert_includes news, "### ➖ Removed since v1.0.0-hbr.1\n\n- `feature/old`: 🗄️ retired"
    assert_includes news, "1 new upstream commit"
    assert_includes news, "- Upstream change"
  end

  def test_tagged_build_names_its_release_and_compares_with_the_one_before
    git "tag", "v1.0.0-hbr.2"
    text, = generate

    assert_includes text, "- 🏷️ **Release:** `v1.0.0-hbr.2`\n"
    assert_includes text, "## 🆕 What's new since v1.0.0-hbr.1"
  end

  def test_same_inputs_give_the_same_file
    assert_equal generate.first, generate.first
  end

  def test_escapes_awkward_titles_for_each_context
    git "checkout", "--quiet", "hbr/platform"
    commit "fork/catalog.yml", CATALOG.sub("title: Alpha screens", %(title: '[A|b] "c" <d> #e *f*_')), "Awkward title"
    integrate "feature/alpha", "feature/beta"
    text, = generate

    assert_includes text, %(f1["🅰️ [A|b] #quot;c#quot; #lt;d#gt; #35;e *f*_<br/>feature/alpha"])
    assert_includes text, "| [🅰️ \\[A\\|b\\] \"c\" &lt;d&gt; #e \\*f\\*\\_](#feature-alpha) |"
    assert_includes text, "### 🅰️ \\[A|b\\] \"c\" &lt;d&gt; #e \\*f\\*\\_\n"
    assert_includes text, "[🅰️ \\[A|b\\] \"c\" &lt;d&gt; #e \\*f\\*\\_](#feature-alpha)"
  end

  def test_refuses_when_an_input_branch_carries_the_changelog
    git "checkout", "--quiet", "hbr/platform"
    commit "HBR-CHANGELOG.md", "oops\n", "Add changelog by mistake"

    error = assert_raises(ForkChangelog::Error) { generate }
    assert_match "HBR-CHANGELOG.md is committed on hbr/platform", error.message
  end

  def test_no_sample_data_section_or_warning_before_the_loader_exists
    text, warnings = generate

    refute_includes text, "Try this build"
    refute(warnings.any? { |warning| warning.include?("sample data") })
  end

  def test_sample_data_section_and_missing_file_warning
    git "checkout", "--quiet", "hbr/platform"
    write "fork/sample_data/sample_data.rb", "# loader\n"
    commit "fork/sample_data/features/alpha.rb", "# alpha data\n", "Add sample data"
    text, warnings = generate

    assert_includes text, "[Try this build](#try)"
    assert_includes text, "## 🧪 Try this build"
    assert_includes text, "bin/rails hbr:sample_data"
    assert_includes warnings, "feature/beta has no sample data in fork/sample_data/features/"
    refute_includes warnings, "feature/alpha has no sample data in fork/sample_data/features/"
  end

  private

  def generate
    generator = ForkChangelog::Generator.new(git: ForkChangelog::Git.new(@dir), ref: "hbr/platform", rev: "hbr/integration")
    [ generator.generate, generator.warnings ]
  end

  def integrate(*branches)
    git "checkout", "--quiet", "-B", "hbr/integration", "upstream-main"
    git "merge", "--quiet", "--no-ff", "-m", "Integrate hbr/platform", "hbr/platform"
    branches.each { |branch| git "merge", "--quiet", "--no-ff", "-m", "Integrate #{branch}", branch }
  end

  def write(path, content)
    FileUtils.mkdir_p(File.join(@dir, File.dirname(path)))
    File.write(File.join(@dir, path), content)
  end

  def commit(path, content, message)
    write(path, content)
    commit_all(message)
  end

  def commit_all(message)
    git "add", "--all"
    git "commit", "--quiet", "-m", message
  end

  def git(*args)
    @time += 60
    date = "#{@time} +0000"
    env = GIT_ENV.merge("GIT_AUTHOR_DATE" => date, "GIT_COMMITTER_DATE" => date)
    out, err, status = Open3.capture3(env, "git", *args, chdir: @dir)
    raise "git #{args.join(" ")} failed: #{err}" unless status.success?

    out
  end
end
