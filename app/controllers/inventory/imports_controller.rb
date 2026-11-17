# CSV import of items for inventory managers (spec §3.11): upload, preview,
# then import. The preview carries the file's text back in the form, so
# nothing is stored between the two steps.
module Inventory
  class ImportsController < BaseController
    # GET /inventory/import/new
    def new
      authorize :inventory, :import?
      @import = Inventory::Import.new(person: current_person, team_id: managed_teams.first&.id)
    end

    # POST /inventory/import
    def create
      authorize :inventory, :import?
      text = params[:file].respond_to?(:read) ? params[:file].read : params[:csv].to_s
      @import = Inventory::Import.new(person: current_person, team_id: params[:team_id], text: text)

      if !@import.valid?
        render :new, status: :unprocessable_entity
      elsif params[:confirm].present?
        result = @import.apply!
        notice = "Imported: #{helpers.pluralize(result.created, "new item")}, #{helpers.pluralize(result.updated, "item")} updated."
        alert = "Skipped #{helpers.pluralize(result.skipped.size, "row")}: #{result.skipped.to_sentence}" if result.skipped.any?
        redirect_to inventory_items_path, notice: notice, alert: alert, status: :see_other
      else
        render :preview, status: :unprocessable_entity
      end
    end
  end
end
