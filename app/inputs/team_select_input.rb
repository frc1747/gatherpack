# A team dropdown for a form without an object, such as the Settings page.
# A blank value means no team.
class TeamSelectInput < SimpleForm::Inputs::CollectionSelectInput
  def input(wrapper_options = nil)
    options[:selected] = input_html_options.delete(:value).to_s
    options[:include_blank] = false
    options[:collection] ||= [ [ "Anyone signed in", "" ] ] + Team.order(:name).pluck(:name, :id)
    super
  end
end
