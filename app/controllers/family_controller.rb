# One page for a guardian's children. It reads and links: every action opens
# the existing page for it, so there's one path and one set of rules.
class FamilyController < InternalController
  before_action :require_feature, :require_wards

  # GET /family
  def show
    authorize :family
  end

  private

  def require_feature
    redirect_to root_path unless MyGatherpack.enabled?
  end

  def require_wards
    redirect_to root_path unless policy(:family).show?
  end
end
