# A team picker for the intake_kiosk_users_team setting: stores the team's
# id, so two teams with the same name can't be confused. Blank means "use
# the time kiosk's team".
class IntakeTeamInput < SimpleForm::Inputs::CollectionSelectInput
  def input(wrapper_options)
    merged = merge_wrapper_options(input_html_options, wrapper_options)
    merged[:class] = Array(merged[:class]) + [ "form-select" ]
    selected = merged.delete(:value)
    options = template.options_from_collection_for_select(Team.order(:name), :id, :name, selected)
    blank = template.content_tag(:option, "Same as the time kiosk", value: "")
    @builder.select(attribute_name, blank + options, {}, merged)
  end
end
