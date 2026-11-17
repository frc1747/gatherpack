class OauthApplication < Doorkeeper::Application
  has_neat_id :oap

  # Doorkeeper reads blank scopes as "no restriction", so an application with
  # none could ask for every scope.
  validate :at_least_one_scope

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "updated_at" ]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end

  def identifier_name
    name
  end

  def selected_scopes
    scopes.to_a
  end

  def selected_scopes=(names)
    self.scopes = Array(names).reject(&:blank?).join(" ")
  end

  private

  def at_least_one_scope
    errors.add(:selected_scopes, "Choose at least one scope.") if selected_scopes.empty?
  end
end
