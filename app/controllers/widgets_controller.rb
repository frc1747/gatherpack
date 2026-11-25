class WidgetsController < InternalController
  before_action :require_widgets_feature
  before_action :set_widget, only: %i[ show edit update destroy ]

  # GET /widgets
  def index
    authorize Widget
    @widgets = policy_scope(Widget).includes(:team).in_order.group_by(&:placement)
  end

  # GET /widgets/1 (a preview of the widget alone)
  def show
  end

  # GET /widgets/1/body (the content of the widget's dashboard card)
  def body
    @widget = Widget.find(params[:id])
    authorize @widget, :body?
    render layout: false
  end

  # GET /widgets/new
  def new
    @widget = authorize Widget.new(placement: params[:placement].presence || "right")
  end

  # GET /widgets/1/edit
  def edit
  end

  # POST /widgets
  def create
    @widget = authorize Widget.new(widget_params)

    if @widget.save
      redirect_to @widget, notice: "Widget was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /widgets/1
  def update
    if @widget.update(widget_params)
      redirect_to @widget, notice: "Widget was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /widgets/1
  def destroy
    @widget.destroy!
    redirect_to widgets_url, notice: "Widget was successfully destroyed.", status: :see_other
  end

  private
    def require_widgets_feature
      redirect_to root_path, notice: "Dashboard widgets are turned off" unless GatherPack::Features.enabled?(:widgets)
    end

    def set_widget
      @widget = authorize Widget.find(params[:id])
    end

    # ERB and JavaScript run code, so only architects can turn them on or
    # change them. That includes the content of a widget that already runs
    # as ERB.
    def widget_params
      fields = [ :title, :show_title, :stylesheet, :style_mode, :refresh_seconds, :placement, :position, :viewer, :team_id, :enabled ]
      if architect?
        fields += [ :content, :dynamic, :javascript ]
      elsif !@widget&.dynamic
        fields << :content
      end
      params.require(:widget).permit(*fields)
    end
end
