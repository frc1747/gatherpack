class GatewayPolicy < ArchitectPolicy
  def webhook?
    true
  end

  # Throwing away secrets that can't be decrypted, for every gateway type.
  def clear_secrets?
    user&.architect
  end
end
