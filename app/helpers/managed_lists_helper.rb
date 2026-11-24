module ManagedListsHelper
  # Row buttons on the managed list screen, sized for a finger.
  MANAGED_LIST_BUTTON_STYLE = "min-width: 44px; min-height: 44px;".freeze

  # A picker for a column that points at a managed list. Offers the active
  # rows in order, plus the record's current row when it has been retired,
  # and, for people who can manage the list, a "Manage <things>" link.
  #
  #   <%= managed_list_select f, :stock_unit_id, list: :stock_units %>
  def managed_list_select(form, attribute, list:, **options)
    managed_list = GatherPack::ManagedLists.find(list) or raise ArgumentError, "No managed list #{list}"
    current_id = form.object&.public_send(attribute)
    choices = managed_list_choices(managed_list, current_id)

    if managed_list.allowed?(current_user)
      manage = link_to("Manage #{managed_list.plural_label.downcase}", managed_list_path(managed_list.key))
      options[:hint] = options[:hint].present? ? safe_join([ options[:hint], " ", manage ]) : manage
    end

    if form.respond_to?(:input)
      form.input attribute, { collection: choices, include_blank: true }.merge(options)
    else
      hint = options.delete(:hint)
      safe_join([ form.select(attribute, choices, { include_blank: true }.merge(options)), (tag.div(hint, class: "form-text") if hint) ])
    end
  end

  # [[label, id], ...] for a picker: active rows in order, then the current
  # row marked "(retired)" if it is no longer active.
  def managed_list_choices(managed_list, current_id = nil)
    model = managed_list.model
    rows = model.active.ordered.to_a
    if current_id.present? && rows.none? { |row| row.id == current_id }
      current = model.find_by(id: current_id)
      rows << current if current
    end
    rows.map { |row| [ managed_list_row_label(row), row.id ] }
  end

  def managed_list_row_label(row)
    row.retired? ? "#{row.name} (retired)" : row.name
  end
end
