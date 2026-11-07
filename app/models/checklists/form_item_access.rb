module Checklists
  # An organizer may make an item read only forms they may see the setup of
  # (FormPolicy::Scope: forms they manage or run as their creator), so an
  # item can't reveal who did a form its organizer can't see. Forms already
  # on the item stay. Checked on save and on the live preview. Included in
  # ChecklistItemsController.
  module FormItemAccess
    extend ActiveSupport::Concern

    included do
      before_action :refuse_forms_out_of_reach, only: %i[ create update preview ]
    end

    private

    def refuse_forms_out_of_reach
      kind = @item&.kind_class || Checklists.item_kind(params.dig(:checklist_item, :kind))
      keys = Array(kind&.settings).select { |setting| setting.type == :forms }.map { |setting| setting.key.to_s }
      return if keys.empty?

      config = params.dig(:checklist_item, :config)
      wanted = keys.flat_map { |key| Array(config.respond_to?(:[]) ? config[key] : nil) }.compact_blank.map(&:to_s)
      kept = previewed_or_saved_item_form_ids(keys)
      unknown = (wanted - kept).uniq
      return if unknown.empty? || policy_scope(Form).where(id: unknown).count == unknown.size

      message = "You can only choose forms you manage."
      if action_name == "preview"
        render plain: message, status: :forbidden
      else
        redirect_to checklist_path(@checklist), alert: message, status: :see_other
      end
    end

    def previewed_or_saved_item_form_ids(keys)
      item = @item || (params[:id].present? && @checklist.checklist_items.find_by(id: params[:id]))
      return [] unless item

      keys.flat_map { |key| Array(item.config[key]) }.map(&:to_s)
    end
  end
end
