class PersonMergesController < InternalController
  before_action :check_feature_enabled

  # GET /person_merges/new
  # With two people chosen, shows what the merge would move and remove.
  def new
    @person_merger = authorize PersonMerger.new(person_merger_params)
    @person_merger.validate if @person_merger.keep_nid.present? || @person_merger.drop_nid.present?
  end

  # POST /person_merges
  def create
    @person_merger = authorize PersonMerger.new(person_merger_params)

    if @person_merger.merge(actor: true_user)
      redirect_to @person_merger.keep, notice: "#{@person_merger.drop.display_name} was merged into #{@person_merger.keep.display_name}.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def check_feature_enabled
    redirect_to root_path, notice: "Merging people is turned off." unless GatherPack::Features.enabled?(:person_merge)
  end

  def person_merger_params
    params.fetch(:person_merger, {}).permit(:keep_nid, :drop_nid, :keep_login)
  end
end
