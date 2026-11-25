# Lets a gateway type choose the input its edit form shows for a setting
# (app/views/gateways/_form.html.erb). Included into Gateway from
# config/initializers/accounting.rb. A type overrides field_input and
# returns, for a field it wants to show differently:
#
#   { label: "Which teams' ledgers", hint: "Plain directions.",
#     as: :check_boxes,                 # or :select
#     choices: [ [ "Label", "value" ], ... ],
#     selected: [ "value", ... ],       # the values shown as chosen
#     include_blank: "None" }           # :select only
#
# A check-box field is posted as an array; permit it through extra_params
# ({ field: [] }). nil keeps the plain text input.
module GatewayFieldInput
  def field_input(field)
    nil
  end
end
