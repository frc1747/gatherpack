class OauthApplication < Doorkeeper::Application
  has_neat_id :oap

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "updated_at" ]
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
end
