class PersonFieldGroupPolicy < AdminPolicy
  def move?
    update?
  end
end
