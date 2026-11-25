module Orders
  # The requester's side of a request (spec §3.16, §3.12 member): New
  # request with its autosaved draft, editing, My requests, and the actions
  # a requester or follower takes from the request page. Every change goes
  # through the request's domain actions (Orders::RequestForm for the form).
  class RequestsController < BaseController
    # Each member action's permission is the policy question of the same
    # name; edit asks update?, unfollow asks follow?.
    POLICY_FOR = { "edit" => :update?, "unfollow" => :follow? }.freeze

    before_action :set_order_request, except: %i[index new create]

    # GET /orders/requests
    # The requests the viewer can see; mine=1 (My requests) limits them to
    # their own and those they follow.
    def index
      authorize OrderRequest
      @order_requests = policy_scope(OrderRequest).includes(:team, :order_lines).order(updated_at: :desc)
      if params[:mine].present?
        person = current_person
        @order_requests = @order_requests.where(requested_by: person)
          .or(@order_requests.where(id: OrderRequestWatcher.where(person: person).select(:order_request_id)))
      end
      @order_requests = @order_requests.page(params[:page])
    end

    # GET /orders/requests/new
    # ?url= opens the form with that link already pasted, its store and part
    # number filled in where a vendor knows them.
    def new
      @order_request = authorize OrderRequest.new(requested_by: current_person, team: default_team)
      @order_request.order_lines.build(prefilled_line_attributes)
    end

    # POST /orders/requests
    # Saves a new draft (autosave sends JSON), and submits it when the
    # form's Submit button sent it.
    def create
      @order_request = authorize OrderRequest.new(requested_by: current_person, team: default_team)
      @form = Orders::RequestForm.new(@order_request, by: current_person, params: request_params)
      if request.format.json? && @form.blank?
        render json: { skipped: true }
      elsif @form.save
        @order_request = @form.order_request
        saved
      else
        not_saved(:new)
      end
    end

    # GET /orders/requests/1
    def show
    end

    # GET /orders/requests/1/edit
    def edit
    end

    # PATCH /orders/requests/1
    def update
      authorize @order_request, submit_policy if submitting?
      @form = Orders::RequestForm.new(@order_request, by: current_person, params: request_params)
      if @form.save
        saved
      else
        not_saved(:edit)
      end
    end

    # DELETE /orders/requests/1
    # Only a draft; anything else is cancelled.
    def destroy
      @order_request.discard_draft!(by: current_person)
      redirect_to orders_requests_path(mine: 1), notice: "Draft deleted"
    end

    # POST /orders/requests/1/submit
    def submit
      @order_request.submit!(by: current_person)
      redirect_to orders_request_path(@order_request), notice: "Sent for approval"
    end

    # POST /orders/requests/1/resubmit
    def resubmit
      @order_request.resubmit!(by: current_person, comment: params[:comment])
      redirect_to orders_request_path(@order_request), notice: "Sent back for approval"
    end

    # POST /orders/requests/1/cancel
    def cancel
      @order_request.cancel!(by: current_person, reason: params[:reason])
      redirect_to orders_request_path(@order_request), notice: "Request cancelled"
    end

    # POST /orders/requests/1/comment
    def comment
      @order_request.comment!(params[:comment], by: current_person)
      redirect_to orders_request_path(@order_request, anchor: "timeline")
    end

    # POST /orders/requests/1/order_again
    # Duplicate: a new draft with the same items, for the same team when the
    # requester can still ask for it, and the same funding source when they
    # may pick funding.
    def order_again
      access = Orders::Access.for(current_person)
      team = access.may_request_for?(@order_request.team_id) ? @order_request.team : default_team
      funding_source = @order_request.funding_source if policy(@order_request).see_funding? && @order_request.funding_source&.usable_by?(team)
      draft = @order_request.order_again(by: current_person, team: team, funding_source: funding_source)
      redirect_to edit_orders_request_path(draft), notice: "Duplicated. Check it, then save."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to orders_request_path(@order_request), alert: e.record.errors.full_messages.to_sentence
    end

    # POST /orders/requests/1/follow
    def follow
      @order_request.follow!(current_person)
      redirect_to orders_request_path(@order_request), notice: "You're following this request"
    end

    # DELETE /orders/requests/1/follow
    def unfollow
      @order_request.unfollow!(current_person)
      redirect_to orders_request_path(@order_request), notice: "You've stopped following this request"
    end

    private

    def set_order_request
      @order_request = policy_scope(OrderRequest)
        .includes(:team, :requested_by, :order_approvals, :funding_source, order_request_watchers: :person,
          order_lines: [ :vendor, :purchase, :item, { photo_attachment: :blob, order_deliveries: :delivery_problem_kind } ])
        .find(params[:id])
      authorize @order_request, POLICY_FOR.fetch(action_name, :"#{action_name}?")
    end

    def current_person
      current_user.person
    end

    # The requester's first team they may ask for.
    def default_team
      ids = Orders::Access.for(current_person).request_team_ids
      teams = current_person&.teams.to_a
      teams.find { |team| ids.nil? || ids.include?(team.id) } || (ids && Team.where(id: ids.to_a).order(:name).first)
    end

    def request_params
      line_fields = Orders::RequestForm::LINE_FIELDS +
        %w[id _destroy vendor_choice other_vendor_name estimated_unit_price photo item_type item_id]
      params.fetch(:order_request, {}).permit(*Orders::RequestForm::REQUEST_FIELDS, lines: line_fields)
    end

    def prefilled_line_attributes
      url = Orders::RequestForm.normalize_url(params[:url].to_s.strip)
      return { quantity: 1 } unless OrderLine.web_link?(url)

      vendor = Vendor.for_url(url)
      { url: url, quantity: 1, vendor: vendor, vendor_part_number: vendor&.part_number_from(url),
        other_vendor_name: vendor ? nil : Vendor.host_of(url) }
    end

    def submitting?
      params[:submit_request].present?
    end

    def submit_policy
      @order_request.changes_requested? ? :resubmit? : :submit?
    end

    def saved
      respond_to do |format|
        format.json { render json: autosave_json }
        format.html do
          if submitting?
            send_for_approval
          else
            redirect_to (@order_request.draft? ? edit_orders_request_path(@order_request) : orders_request_path(@order_request)),
              notice: "Saved"
          end
        end
      end
    end

    def send_for_approval
      if @order_request.changes_requested?
        @order_request.resubmit!(by: current_person)
        redirect_to orders_request_path(@order_request), notice: "Sent back for approval"
      elsif @order_request.draft?
        @order_request.submit!(by: current_person)
        redirect_to orders_request_path(@order_request), notice: "Sent for approval"
      else
        redirect_to orders_request_path(@order_request), notice: "Saved"
      end
    rescue Orders::Refused, ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.is_a?(Orders::Refused) ? e.message : e.record.errors.full_messages.to_sentence
      @order_request = OrderRequest.find(@order_request.id)
      render :edit, status: :unprocessable_entity
    end

    def not_saved(template)
      respond_to do |format|
        format.json { render json: { errors: @form.errors }, status: :unprocessable_entity }
        format.html do
          flash.now[:alert] = @form.errors.to_sentence
          @lines = @form.display_lines
          render template, status: :unprocessable_entity
        end
      end
    end

    def autosave_json
      {
        id: @order_request.to_param,
        update_url: orders_request_path(@order_request),
        edit_url: edit_orders_request_path(@order_request),
        lines: @form.line_ids,
        removed: @form.removed_keys
      }
    end
  end
end
