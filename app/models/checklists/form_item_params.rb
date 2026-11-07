module Checklists
  # Keeps the list of forms a form item names (a :forms setting) when the
  # item is saved or previewed. Prepended to ChecklistItemsController.
  module FormItemParams
    private

    def config_params
      kind = @item&.kind_class || Checklists.item_kind(params.dig(:checklist_item, :kind))
      config = params.dig(:checklist_item, :config)
      keys = Array(kind&.settings).select { |setting| setting.type == :forms }.map { |setting| { setting.key => [] } }
      return super if keys.empty? || !config.respond_to?(:permit)

      super.merge(config.permit(*keys).to_h)
    end
  end
end
