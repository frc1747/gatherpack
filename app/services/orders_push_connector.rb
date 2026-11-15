# Prepended to OrderNotices from config/initializers/orders_push.rb. Every
# orders notice also goes to the phones of the people it is for, on top of the
# emails. Who hears about what is decided by OrderNotices; this only follows it.
# The emails are queued first, and a failure here can't stop them. A person
# needs no email address or email gateway to get a push.
module OrdersPushConnector
  ENTRY_POINTS = %i[
    submitted step_approved approved changes_requested declined ordered backordered
    received problem needs_reapproval needed_soon undecided buyer_digest
  ].freeze

  ENTRY_POINTS.each do |name|
    define_method(name) do |*args, **options|
      @push_path = push_path_for(args.first)
      super(*args, **options)
    ensure
      @push_path = nil
    end
  end

  private
    # Returns how many people the notice reached by email, push or both, so
    # a reminder is marked as sent when only a push went out.
    def deliver(people, subject, by: nil)
      emailed = super
      recipients = people.compact.uniq.reject { |person| person == by }
      pushed = push(recipients, subject)
      reached = pushed | (emailed.positive? ? recipients.select { |person| person.user&.email.present? } : [])
      reached.size
    end

    # The people a push was queued for.
    def push(recipients, subject)
      return [] unless Orders.enabled? && GatherPack::PushChannel.available? && @push_path

      recipients.select do |person|
        GatherPack::PushChannel.deliver(person, topic: :orders, title: subject, path: @push_path).to_i.positive?
      end
    rescue StandardError => e
      Rails.logger.error("Orders phone notifications failed: #{e.class}: #{e.message}")
      []
    end

    # The request, or one of its lines, opens the request; the digest opens To buy.
    def push_path_for(subject)
      urls = Rails.application.routes.url_helpers
      case subject
      when OrderRequest then urls.orders_request_path(subject)
      when OrderLine then urls.orders_request_path(subject.order_request)
      else urls.to_buy_orders_purchases_path
      end
    end
end
