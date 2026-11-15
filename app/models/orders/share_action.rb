# "Ask to buy this" in the share list: a link shared to the installed app opens
# the new request form with that link already pasted.
module Orders
  module ShareAction
    KEY = :orders_request

    def self.register
      return unless defined?(GatherPack::ShareActions)

      GatherPack::ShareActions.register(KEY, label: "Ask to buy this", visible: method(:visible?), path: method(:path))
    end

    def self.visible?(user)
      Orders.enabled? && Orders::Access.for(user&.person).requester?
    end

    def self.path(shared)
      Rails.application.routes.url_helpers.new_orders_request_path(url: shared.url.presence)
    end
  end
end
