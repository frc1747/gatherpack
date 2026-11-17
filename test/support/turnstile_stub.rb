# Replaces the adapter's HTTP call for a block, so no test reaches Cloudflare.
# The result is the response body, or a proc that returns it or raises.
module TurnstileStub
  def stub_turnstile(adapter, result)
    sent = []
    adapter.define_singleton_method(:post) do |form|
      sent << form
      result.respond_to?(:call) ? result.call : result
    end
    yield sent
  ensure
    adapter.singleton_class.send(:remove_method, :post)
  end
end
