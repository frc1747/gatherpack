# The orders pages' own words for one viewer: status texts, the request total the
# viewer may see, and the timeline lines with the changes they may see. It includes the
# helpers the pages use (OrdersHelper, OrderRequestsHelper, Orders::PurchasesHelper), so
# a tool says exactly what the page says and leaves out what the page leaves out.
# policy is the viewer's, as the views' policy is.
class Mcp::OrderWords
  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::TranslationHelper
  include OrdersHelper
  include OrderRequestsHelper
  include Orders::PurchasesHelper

  def initialize(user)
    @user = user
  end

  def policy(record)
    Pundit.policy!(@user, record)
  end
end
