module MyGatherpack
  # "What have I done this season?": a person's own records, or a ward's for
  # their guardian. Reads only; each row links to the existing page for it.
  class ActivityController < InternalController
    before_action :require_feature, :require_person

    # GET /activity, /activity?person=<neat id>
    def show
      @person = requested_person
      unless ActivityPolicy.new(current_user, @person).show?
        skip_authorization
        return redirect_to(activity_path)
      end

      authorize @person, :show?, policy_class: ActivityPolicy
      @season = requested_season
      @activity = MyGatherpack::Activity.new(@person, season: @season, viewer: current_user.person, viewer_events: policy_scope(Event))
    end

    private

    def require_feature
      redirect_to root_path unless MyGatherpack::Activity.enabled?
    end

    def require_person
      redirect_to root_path if current_user.person.nil?
    end

    # Someone the viewer may not see falls back to the viewer's own page.
    def requested_person
      return current_user.person if params[:person].blank?

      Person.find_by_neat_id(params[:person].to_s) || current_user.person
    rescue ArgumentError
      current_user.person
    end

    def requested_season
      year = params[:season].to_s
      year.match?(/\A\d{4}\z/) ? MyGatherpack::Season.starting_in(year.to_i) : MyGatherpack::Season.current
    end
  end
end
