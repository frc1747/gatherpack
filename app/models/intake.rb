# Membership intake: registrations, the entries people make through them, and
# the rules shared by the self-service link and the kiosk.
module Intake
  # Rails.cache by default; tests swap in a memory store (the test cache is
  # a null store, which never counts).
  mattr_accessor :rate_limit_store

  def self.table_name_prefix
    "intake_"
  end

  def self.enabled?
    GatherPack::Features.enabled?(:intake)
  end

  # Integer settings are stored as strings; blank or junk means the default.
  def self.setting(key, default)
    value = Settings[key].to_s.strip
    value.match?(/\A\d+\z/) ? value.to_i : default
  end

  # 128 random bits for a link, and the digest that is all the database keeps.
  def self.new_token
    SecureRandom.urlsafe_base64(16)
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  def self.normalize_email(email)
    email.to_s.strip.downcase
  end

  # The network a request came from, not the address: the first three parts
  # of an IPv4 address, or the first three groups of an IPv6 one.
  def self.ip_prefix(ip)
    address = IPAddr.new(ip.to_s)
    if address.ipv4?
      "#{ip.to_s.split(".").first(3).join(".")}.*"
    else
      "#{address.to_string.split(":").first(3).map { |group| group.sub(/\A0+(?=.)/, "") }.join(":")}:*"
    end
  rescue IPAddr::InvalidAddressError
    nil
  end

  # Whether a person needs a guardian, by the guardianship age limit (18 when
  # unset). No birthday on file means a guardian is needed. A birth year is
  # used when the birthday isn't known, counting the person as the younger of
  # the two ages they could be.
  def self.needs_guardian?(birthday: nil, birth_year: nil)
    limit = Relationship.guardianship_age_limit || 18
    if birthday
      birthday > Date.current - limit.years
    elsif birth_year.to_s.match?(/\A\d{4}\z/)
      Date.current.year - birth_year.to_i <= limit
    else
      true
    end
  end

  def self.person_needs_guardian?(person)
    needs_guardian?(birthday: person.birthday)
  end

  # Runs the hooks registered for a named intake event, while the feature is on.
  def self.fire(event, model)
    return unless enabled?
    Hook.where(event: event).each { |hook| hook.run(model) }
  end

  # Login emails are matched trimmed and case-insensitively. Only jobs and
  # staff screens call this, never a public request (no account enumeration).
  def self.user_for_email(email)
    normalized = normalize_email(email)
    return if normalized.blank?
    User.find_by("LOWER(TRIM(email)) = ?", normalized)
  end

  # A person with no login whose name (and birthday, where both are known)
  # matches: someone who might already be on file. Never attached
  # automatically; staff decide.
  def self.possible_match(first_name:, last_name:, birthday: nil, except: [])
    scope = Person.where(user_id: nil)
      .where("LOWER(TRIM(first_name)) = ? AND LOWER(TRIM(last_name)) = ?", first_name.to_s.strip.downcase, last_name.to_s.strip.downcase)
      .where.not(id: Array(except).compact)
    scope = scope.where(birthday: [ birthday, nil ]) if birthday
    scope.order(:created_at).first
  end
end
