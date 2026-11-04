require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/mcp_page_world"

class Mcp::Tools::GetPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include McpPageWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_page_world
  end

  def page_for(viewer, page, **options)
    call_tool("get_page", user: user(viewer), page_id: page.neat_id, **options)
  end

  test "each role opens what its level allows, and anything else is not found" do
    {
      admin: %i[public members alpha_team alpha_managers beta_team admin_only dynamic],
      alpha_manager: %i[public members alpha_team alpha_managers],
      alpha_member: %i[public members alpha_team],
      beta_member: %i[public members beta_team],
      guardian: %i[public members]
    }.each do |viewer, allowed|
      @pages.each do |key, page|
        result = page_for(viewer, page)
        if allowed.include?(key)
          assert_nil result.error, "#{viewer} opening #{key}"
        else
          assert_equal "Not found", result.error, "#{viewer} opening #{key}"
        end
      end
    end
  end

  test "it opens and refuses as the page does" do
    %i[admin alpha_manager alpha_member beta_member guardian].product(@pages.keys).each do |viewer, key|
      sign_in user(viewer)
      get page_path(@pages[key])
      sign_out user(viewer)
      page_opens = response.successful?

      assert_equal page_opens, page_for(viewer, @pages[key]).error.nil?, "#{viewer} opening #{key}"
    end
  end

  test "a static page comes back as text with its details" do
    page = create_page("Static", team: @alpha, content: "# Heading\n\nSome *words* here.")

    assert_equal({
      "id" => page.neat_id,
      "title" => "Static",
      "team" => { "id" => @alpha.neat_id, "name" => "Alpha" },
      "dynamic" => false,
      "content" => "Heading\n\nSome words here.",
      "truncated" => false
    }, page_for(:admin, page).value)
  end

  test "a dynamic page renders as the token's user, with their permissions" do
    page = erb_page(<<~ERB)
      Hello <%= current_user.person.first_name %>.
      Admin: <%= admin? %>. Page: <%= @page.title %>.
      <% if policy(Page.new(viewer: "user", editor: "admin")).update? %>can edit<% else %>can't edit<% end %>
      People: <%= policy_scope(Team).where(name: "Beta").count %>
    ERB

    admin = page_for(:admin, page).value["content"]
    assert_includes admin, "Hello Admin."
    assert_includes admin, "Admin: true."
    assert_includes admin, "Page: #{page.title}."
    assert_includes admin, "can edit"

    member = page_for(:alpha_member, page).value["content"]
    assert_includes member, "Hello AlphaMember."
    assert_includes member, "Admin: false."
    assert_includes member, "can't edit"
    assert_includes member, "People: 0"
  end

  test "a dynamic page renders the same words as a browser's GET" do
    page = erb_page("<p>For <%= current_user.person.first_name %>: <%= params[:term] %>, <%= Time.zone.name %></p>")
    sign_in user(:alpha_member)
    get page_path(page, term: "fall")

    content = page_for(:alpha_member, page, params: { term: "fall" }).value["content"]
    assert_match(/\AFor AlphaMember: fall, \S+\z/, content)
    assert response.body.include?(content), "the page's words differ from #{content}"
  end

  test "what a page does runs as the token's user" do
    page = erb_page(%(<% Announcement.create!(title: "From a page", content: "x", start_time: Time.current, end_time: Time.current) %>done))

    assert_equal "done", page_for(:alpha_member, page).value["content"]
    assert_equal user(:alpha_member).id, Announcement.find_by!(title: "From a page").versions.last.whodunnit
  end

  test "params are the query string, values strings only, and can't change which page it is" do
    page = erb_page("<%= params[:a] %>/<%= params.dig(:n, :m) %>/<%= params[:id] == @page.to_param %>/<%= request.query_parameters.keys.sort.join(',') %>")

    content = page_for(:admin, page, params: { "a" => "x y&z", "n[m]" => "deep", "id" => @pages[:admin_only].neat_id }).value["content"]
    assert_equal "x y&z/deep/true/a,id,n", content

    assert_match(/string/, page_for(:admin, page, params: { "a" => 1 }).error)
    assert_match(/string/, page_for(:admin, page, params: { "a" => [ "x" ] }).error)
    assert_match(/params/, page_for(:admin, page, params: "a=1").error)
    assert_equal "params aren't a valid query string", page_for(:admin, page, params: { "a" => "1", "a[b]" => "2" }).error
  end

  test "there's no session, cookie or layout, and reading them finds nothing" do
    page = erb_page("[<%= session[:user_return_to].inspect %>][<%= cookies[:theme].inspect %>][<%= flash[:notice].inspect %>]")

    assert_equal "[nil][nil][nil]", page_for(:alpha_member, page).value["content"]
    assert_not_includes page_for(:alpha_member, @pages[:public]).value["content"], "Sign out"
  end

  test "a page's own refusal is a refusal" do
    page = erb_page("<% raise Pundit::NotAuthorizedError %>")

    assert_equal "Not allowed", page_for(:alpha_member, page).error
    assert_equal "denied", McpToolCall.order(:created_at).last.outcome
  end

  test "a render error is a tool error without the exception's text, and is logged" do
    page = erb_page(%(<% raise "the secret detail" %>))
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io, level: :error)
    Rails.logger.broadcast_to(sink)

    result = page_for(:alpha_member, page)

    assert_equal "This page couldn't be rendered", result.error
    assert_equal "error", McpToolCall.order(:created_at).last.outcome
    assert_not_includes McpToolCall.order(:created_at).last.error_message, "secret"
    assert_includes io.string, page.neat_id
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  test "errors that aren't StandardError don't escape" do
    [ "<% exit %>", "<% def f = f; f %>", "<% raise NotImplementedError %>", "<% raise Exception %>" ].each do |content|
      assert_equal "This page couldn't be rendered", page_for(:alpha_member, erb_page(content)).error, content
    end
  end

  test "a syntax error shows the page's own message, as on the site" do
    page = erb_page("<% if %>")
    sign_in user(:alpha_member)
    get page_path(page)
    assert_includes response.body, "Syntax error in page content"

    assert_includes page_for(:alpha_member, page).value["content"], "Syntax error in page content"
  end

  test "a slow render is stopped and reported, sleeping or looping, and the next call works" do
    with_time_limit(0.2) do
      [ "<% sleep 30 %>", "<% loop { } %>", "<% begin; sleep 30; rescue Exception; sleep 30; end %>" ].each do |content|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        result = page_for(:alpha_member, erb_page(content))

        assert_match(/took longer than 0\.2 seconds .* stopped/, result.error, content)
        assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
        assert_equal "error", McpToolCall.order(:created_at).last.outcome
      end

      assert_nil page_for(:alpha_member, @pages[:public]).error
    end
  end

  test "the limit is 10 seconds" do
    assert_equal 10, Mcp::PageRender.time_limit
  end

  test "output over 200 KB is cut on a character boundary" do
    page = erb_page(%(<%= "é" * 150_000 %>))

    value = page_for(:alpha_member, page).value
    assert value["truncated"]
    assert_operator value["content"].bytesize, :<=, 200.kilobytes
    assert_operator value["content"].bytesize, :>, 199.kilobytes
    assert value["content"].valid_encoding?
  end

  test "HTML too big to convert is cut too, and a smaller page isn't" do
    assert page_for(:alpha_member, erb_page(%(<%= raw("<p>a</p>" * 400_000) %>))).value["truncated"]
    assert_not page_for(:alpha_member, erb_page(%(<%= "a" * 1000 %>))).value["truncated"]
  end

  test "invalid IDs are not found, and the feature being off refuses it" do
    [ "nonsense", "pg_nonsense", @alpha.neat_id ].each { |bad| assert_equal "Not found", call_tool("get_page", user: user(:admin), page_id: bad).error }
    with_feature(:pages, false) { assert_equal "Feature off", page_for(:admin, @pages[:public]).error }
  end

  private

  def with_time_limit(seconds)
    original = Mcp::PageRender.time_limit
    Mcp::PageRender.time_limit = seconds
    yield
  ensure
    Mcp::PageRender.time_limit = original
  end
end
