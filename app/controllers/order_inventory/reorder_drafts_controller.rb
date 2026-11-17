# Order these, from the reorder list (inventory spec §3.5): a page to check
# the ticked items and their quantities, then a draft request made through
# OrderRequest.draft_for for the requester to finish and submit.
module OrderInventory
  class ReorderDraftsController < BaseController
    before_action :set_rows

    # GET /order_inventory/reorder_drafts/new?items[id]=quantity
    def new
      authorize OrderRequest, :create?
      @teams = team_options
      @team_id = default_team_id
    end

    # POST /order_inventory/reorder_drafts
    def create
      authorize OrderRequest, :create?
      team = Team.find_by(id: params[:team_id])
      raise Orders::Refused, "Pick a team you can ask for" unless team && access.may_request_for?(team.id)
      raise Orders::Refused, "Tick at least one item" if @rows.empty?

      lines = @rows.map { |item, quantity| OrderInventory.line_attributes(item).merge(quantity: quantity) }
      draft = OrderRequest.draft_for(person: current_user.person, team: team, lines: lines)
      redirect_to edit_orders_request_path(draft), notice: "Draft started with #{helpers.pluralize(lines.size, 'item')}. Check it and submit it for approval."
    rescue ActiveRecord::RecordInvalid => error
      raise Orders::Refused, error.record.errors.full_messages.to_sentence
    end

    private

    # [[item, quantity]] for the ticked items the viewer sees, in the order
    # given; a blank or non-positive quantity drops the item.
    def set_rows
      raw = params[:items]
      wanted = raw.is_a?(ActionController::Parameters) ? raw.permit(*raw.keys).to_h : {}
      items = policy_scope(Item).active.where(id: wanted.keys).includes(:item_sources).index_by(&:id)
      @rows = wanted.filter_map do |id, quantity|
        count = Integer(quantity.to_s, 10, exception: false)
        [ items[id], count ] if items[id] && count&.positive?
      end
    end

    def access
      Orders::Access.for(current_user.person)
    end

    def team_options
      ids = access.request_team_ids
      (ids.nil? ? Team.all : Team.where(id: ids.to_a)).order(:name)
    end

    # The items' own team when they share one the viewer may ask for, else
    # the viewer's first team.
    def default_team_id
      teams = @rows.map { |item, _| item.team_id }.uniq
      return teams.first if teams.one? && access.may_request_for?(teams.first)

      @teams.first&.id
    end
  end
end
