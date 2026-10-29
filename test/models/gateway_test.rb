require "test_helper"

class GatewayTest < ActiveSupport::TestCase
  test "gateways that don't receive webhooks refuse every webhook request" do
    [ Gateway::SmtpSendingGateway.new, Gateway::PostmarkSendingGateway.new(api_token: "pm-token") ].each do |gateway|
      assert_not gateway.verify_webhook("{}", {}), "#{gateway.class} accepted a webhook request"
    end
  end
end
