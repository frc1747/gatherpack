# Search and filter forms are never required to be filled in, so don't mark
# their inputs as required (SimpleForm marks everything required by default).
module SearchFormHelper
  def search_form_for(record, options = {}, &)
    options[:defaults] = { required: false }.merge(options[:defaults] || {})
    super
  end
end
