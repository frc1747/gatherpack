# frozen_string_literal: true

# The share landing page. Any signed-in person may open it; each action on it
# decides for itself who sees it (GatherPack::ShareActions).
class SharePolicy < ApplicationPolicy
  def show?
    user.present?
  end
end
