require "test_helper"

class FeatureRoutesTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir
    Rails.application.routes.draw_paths << Pathname.new(@dir)
  end

  teardown do
    Rails.application.routes.draw_paths.delete(Pathname.new(@dir))
    GatherPack::Features.instance_variable_get(:@plugins).delete(:route_seam_test)
    FileUtils.remove_entry(@dir)
    Rails.application.reload_routes!
  end

  test "a file in a routes directory is drawn" do
    File.write(File.join(@dir, "route_seam_test.rb"), %(get "/route_seam_file", to: "welcome#index"\n))
    Rails.application.reload_routes!

    assert_equal "welcome", recognize("/route_seam_file")[:controller]
  end

  test "routes_proc of an enabled feature is drawn" do
    register_feature(enabled: true)
    Rails.application.reload_routes!

    assert_equal "welcome", recognize("/route_seam_proc")[:controller]
  end

  test "routes_proc of a disabled feature is not drawn" do
    register_feature(enabled: false)
    Rails.application.reload_routes!

    assert_raises(ActionController::RoutingError) { recognize("/route_seam_proc") }
  end

  private

  def recognize(path)
    Rails.application.routes.recognize_path(path)
  end

  # Not toggleable, so no setting is added to the global registry.
  def register_feature(enabled:)
    feature = GatherPack::Feature.new(key: :route_seam_test, label: "Route seam", description: "test",
                                      toggleable: false, nav_section: nil,
                                      routes_proc: proc { get "/route_seam_proc", to: "welcome#index" })
    feature.define_singleton_method(:enabled?) { enabled }
    GatherPack::Features.register(feature)
  end
end
