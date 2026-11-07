require "test_helper"

class FeatureRoutesTest < ActionDispatch::IntegrationTest
  teardown do
    GatherPack::Features.instance_variable_get(:@plugins).delete(:route_seam_test)
    FileUtils.rm_f(route_file)
    Rails.application.reload_routes!
  end

  test "a file in config/routes is drawn" do
    File.write(route_file, %(get "/route_seam_file", to: "welcome#index", as: :route_seam_file\n))
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

  def route_file
    Rails.root.join("config/routes/route_seam_test.rb")
  end

  def register_feature(enabled:)
    feature = GatherPack::Feature.new(key: :route_seam_test, label: "Route seam", description: "test",
                                      default_enabled: false, toggleable: !enabled, nav_section: nil,
                                      routes_proc: proc { get "/route_seam_proc", to: "welcome#index", as: :route_seam_proc })
    GatherPack::Features.register(feature)
  end
end
