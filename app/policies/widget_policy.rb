class WidgetPolicy < AdminPolicy
  # Widgets this user sees on the dashboard.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.admin

      scope.where(id: scope.enabled.includes(:team).select { |widget| widget.visible_to?(user) }.map(&:id))
    end
  end

  # Like Pages: everyone signed in sees the list of widgets they can see, and
  # each of those widgets. Only admins create, edit and delete.
  def index?
    user.present?
  end

  def show?
    record.visible_to?(user)
  end

  # The widget's body, as loaded into its dashboard card.
  def body?
    record.visible_to?(user)
  end
end
