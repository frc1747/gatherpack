# What create_person, update_person and add_login share: the steps of
# PeopleController's create and update that apply to the attributes these tools take,
# and building a login.
module Mcp::PersonWrites
  # Well under what the users table's email index can hold, about 2,700 bytes. Past
  # that the page crashes, so this refuses before anything is saved.
  MAX_EMAIL_BYTES = 2_000
  REQUIRED_BLANK = "A required profile field is blank; complete it on their profile page".freeze

  private

  # An unsaved, checked login with a random password nobody sees. Its messages don't
  # quote the email or the password.
  def build_login(email)
    invalid_argument!("Email is too long") if email.bytesize > MAX_EMAIL_BYTES

    user = User.new(email: email, password: Devise.friendly_token[0, 20])
    invalid_argument!(user.errors.full_messages.to_sentence) unless user.valid?
    user
  end

  # The form's single-line inputs don't send line breaks or control characters.
  def refuse_control_characters!(attributes)
    bad = attributes.select { |_name, value| value.is_a?(String) && value.match?(/[[:cntrl:]]/) }.keys
    invalid_argument!("#{bad.to_sentence} can't contain line breaks or control characters") if bad.any?
  end

  # Where the build has person fields, the page's create and update run
  # assign_field_values (with nothing to assign here), whose required check blocks
  # the save. The field isn't named: it may be one withheld from this client
  # (Mcp::MinorRule).
  def save_person(person, required_blank: REQUIRED_BLANK)
    person.assign_field_values({}, acting: ctx.person) if person.respond_to?(:assign_field_values)
    invalid_argument!(required_blank) unless person.save
  end

  # Audit rows live in their own database, so a rollback has to cover both.
  def in_all_databases(&block)
    AuditLog.transaction { ApplicationRecord.transaction(&block) }
  end
end
