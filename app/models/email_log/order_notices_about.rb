module EmailLog
  # Prepended onto OrderNotices: while a notice about a request is being
  # sent, OrderNotices#deliver names that request (@email_about) on each
  # email, so the sent email log can show it on the request's page. Kept out
  # of #deliver's arguments, which connectors prepend onto.
  module OrderNoticesAbout
    NOTICES = %i[submitted step_approved approved changes_requested declined ordered backordered
      received problem needs_reapproval needed_soon undecided].freeze

    NOTICES.each do |notice|
      define_method(notice) do |record, *args, **options, &block|
        about_request(record.is_a?(OrderLine) ? record.order_request : record) { super(record, *args, **options, &block) }
      end
    end

    private
      def about_request(order_request)
        previous, @email_about = @email_about, order_request
        yield
      ensure
        @email_about = previous
      end
  end
end
