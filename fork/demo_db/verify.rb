# Proves the demo database holds no real identities, by comparing it with an
# untouched restore of the same dump (DEMO_SOURCE_URL, a *_demo_source
# database). Exits non-zero on any failed check. Run by bin/fork-make-demo-db.
#
# Env: DEMO_SOURCE_URL, DEMO_PASSWORD, DEMO_PROTECT_TEAM, DEMO_PROTECT_EMAILS,
#      MAILPIT_URL (optional: also proves nothing reaches a local Mailpit).
require "set"
require "net/http"
require_relative "guard"

DemoDb.guard!
PaperTrail.enabled = false
PASSWORD = ENV["DEMO_PASSWORD"].presence || "password123"
PROTECT_TEAM = ENV["DEMO_PROTECT_TEAM"].presence || "Mentors"
PROTECT_EMAILS = ENV["DEMO_PROTECT_EMAILS"].to_s.split(",").map { |email| email.strip.downcase }.reject(&:empty?)
PERSONA_EMAILS = %w[demo.member@example.invalid demo.lead@example.invalid demo.mentor@example.invalid].freeze
DB = ActiveRecord::Base.connection

class SourceRecord < ActiveRecord::Base
  self.abstract_class = true
end
SourceRecord.establish_connection(ENV.fetch("DEMO_SOURCE_URL"))
SRC = SourceRecord.connection
DemoDb.refuse("source isn't a *_demo_source database") unless SRC.current_database.end_with?("_demo_source")

FAILURES = []
def check(label, ok, detail = nil)
  puts format("   [%s] %s%s", ok ? "ok" : "FAIL", label, detail.nil? ? "" : ": #{detail}")
  FAILURES << label unless ok
end

def rows(conn, sql) = conn.select_all(sql).to_a

# --- Who is protected (from the source) ------------------------------------------
puts "== Protected accounts"
quoted_emails = PROTECT_EMAILS.map { |email| SRC.quote(email) }.join(", ").presence || "''"
protected_people = rows(SRC, <<~SQL).map { _1["id"] }.to_set
  select m.person_id as id from memberships m join teams t on t.id = m.team_id where t.name = #{SRC.quote(PROTECT_TEAM)}
  union select p.id from people p join users u on u.id = p.user_id where lower(u.email) in (#{quoted_emails})
SQL
protected_users = rows(SRC, "select user_id as id from people where user_id is not null and id in (#{protected_people.map { SRC.quote(_1) }.join(',')})
  union select id from users where lower(email) in (#{quoted_emails})").map { _1["id"] }.to_set
source_people = rows(SRC, "select id, first_name, last_name, display_name, phone_number, address, birthday from people").index_by { _1["id"] }
source_users = rows(SRC, "select id, email, encrypted_password from users").index_by { _1["id"] }
demo_people = rows(DB, "select id, first_name, last_name, display_name, phone_number, address, birthday from people").index_by { _1["id"] }
demo_users = rows(DB, "select id, email, encrypted_password from users").index_by { _1["id"] }
puts "   protected people #{protected_people.size}, protected users #{protected_users.size}"
check "protected people unchanged", protected_people.all? { |id| source_people[id] == demo_people[id] }
check "protected users keep their email and password", protected_users.all? { |id| source_users[id].slice("email", "encrypted_password") == demo_users[id].slice("email", "encrypted_password") }

# --- Real identities gone -------------------------------------------------------------
puts "== Non-protected people and users"
others = source_people.values.reject { protected_people.include?(_1["id"]) }
other_users = source_users.values.reject { protected_users.include?(_1["id"]) }
real_emails = other_users.map { _1["email"].downcase }.to_set
real_phones = others.filter_map { _1["phone_number"]&.gsub(/\D/, "")&.last(10) }.reject { _1.length < 7 }.to_set
words = ->(text) { text.to_s.scan(/[[:alpha:]][[:alpha:]'’-]*/).map(&:downcase) }
protected_words = source_people.values.select { protected_people.include?(_1["id"]) }.flat_map { words.("#{_1['first_name']} #{_1['last_name']} #{_1['display_name']}") }.to_set
other_words = others.flat_map { words.("#{_1['first_name']} #{_1['last_name']} #{_1['display_name']}") }.to_set - protected_words
real_full_names = others.filter_map { "#{_1['first_name']} #{_1['last_name']}".squish.downcase if _1["first_name"].present? && _1["last_name"].present? }.to_set
real_addresses = others.filter_map { _1["address"]&.split(",")&.first&.squish&.downcase }.to_set

demo_others = others.map { demo_people[_1["id"]] }
check "no real first or last name left on a non-protected person",
  demo_others.none? { |person| (words.("#{person['first_name']} #{person['last_name']} #{person['display_name']}") & (other_words + protected_words).to_a).any? }
check "no person kept their real name", others.none? { |p| demo_people[p["id"]].slice("first_name", "last_name") == p.slice("first_name", "last_name") }
check "no real phone number left", demo_people.values.reject { protected_people.include?(_1["id"]) }.none? { real_phones.include?(_1["phone_number"].to_s.gsub(/\D/, "").last(10)) }
check "no real street address left", demo_others.none? { real_addresses.include?(_1["address"].to_s.split(",").first.to_s.squish.downcase) }
check "birthdays moved", others.select { _1["birthday"] }.none? { demo_people[_1["id"]]["birthday"] == _1["birthday"] }
demo_other_users = demo_users.values_at(*other_users.map { _1["id"] })
check "every non-protected email ends in @example.invalid", demo_other_users.all? { _1["email"].end_with?("@example.invalid") },
  demo_other_users.reject { _1["email"].end_with?("@example.invalid") }.size
check "no real email left on any user", demo_other_users.none? { real_emails.include?(_1["email"].downcase) }
hashes = demo_other_users.map { _1["encrypted_password"] }.uniq
check "every non-protected user has the demo password", hashes.size == 1 && User.new(encrypted_password: hashes.first).valid_password?(PASSWORD)
check "no sessions, reset or remember tokens", DB.select_value("select count(*) from users where reset_password_token is not null or remember_created_at is not null or locked_at is not null").to_i.zero?
check "every session token rotated", rows(SRC, "select id, session_token from users").none? { |row| DB.select_value("select session_token from users where id = #{DB.quote(row['id'])}") == row["session_token"] }
check "no kiosk token kept its value", (rows(SRC, "select value from tokens").map { _1["value"] }.to_set & rows(DB, "select value from tokens").map { _1["value"] }.to_set).empty?
check "every avatar is a placeholder", DB.select_value("select count(*) from active_storage_attachments a join active_storage_blobs b on b.id = a.blob_id where a.record_type = 'Person' and b.filename <> 'avatar.png'").to_i.zero?

# --- Text sweep: every text column in the database ------------------------------------
puts "== Text sweep"
common = File.exist?("/usr/share/dict/words") ? File.foreach("/usr/share/dict/words").map(&:chomp).select { _1.match?(/\A[a-z]+\z/) }.to_set : Set.new
hits = Hash.new { |hash, key| hash[key] = Hash.new(0) }
columns = rows(DB, "select table_name, column_name from information_schema.columns where table_schema = 'public' and data_type in ('text', 'character varying', 'jsonb')")
columns.each do |column|
  table, name = column["table_name"], column["column_name"]
  next if table.start_with?("solid_")
  scope = table == "people" ? " where id not in (#{protected_people.map { DB.quote(_1) }.join(',')})" : ""
  scope = " where id not in (#{protected_users.map { DB.quote(_1) }.join(',')})" if table == "users"
  DB.select_values("select #{DB.quote_column_name(name)}::text from #{DB.quote_table_name(table)}#{scope}").compact.each do |text|
    down = text.downcase
    hits[:emails]["#{table}.#{name}"] += 1 if text.scan(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/).any? { real_emails.include?(_1.downcase) }
    hits[:phones]["#{table}.#{name}"] += 1 if text.scan(/\d[\d\s().-]{8,}\d/).any? { real_phones.include?(_1.gsub(/\D/, "").last(10)) }
    hits[:full_names]["#{table}.#{name}"] += 1 if real_full_names.any? { down.include?(_1) }
    proper = text.scan(/[[:alpha:]][[:alpha:]'’-]*/).select { |word| other_words.include?(word.downcase) && !(common.include?(word.downcase) && word == word.downcase) }
    hits[:name_words]["#{table}.#{name}"] += proper.size if proper.any?
  end
end
check "no real non-protected email anywhere", hits[:emails].empty?, hits[:emails].presence&.to_a
check "no real phone number anywhere", hits[:phones].empty?, hits[:phones].presence&.to_a
check "no real full name anywhere", hits[:full_names].empty?, hits[:full_names].presence&.to_a
check "no real (non-protected) name word anywhere", hits[:name_words].empty?, hits[:name_words].presence&.to_a

# --- Nothing can reach the outside -----------------------------------------------------
puts "== Outside connections"
check "no gateways", Gateway.count.zero?, Gateway.count
check "no OAuth tokens", DB.select_value("select (select count(*) from oauth_access_tokens) + (select count(*) from oauth_access_grants)").to_i.zero?
check "no hook calls an outside service", Hook.where("code ~* 'https?:|net::http|webhook|slack'").none?

# --- Structure unchanged -------------------------------------------------------------
puts "== Row counts (source -> demo)"
expected_changes = /\A(people|users|memberships|badge_assignments|form_responses|form_submissions|form_signatures|signups|signup_sheet_organizers|commitment_[a-z_]+|
  active_storage_[a-z_]+|solid_[a-z_]+|oauth_access_[a-z_]+|gateways|tokens|action_mailbox_inbound_emails)\z/x
SRC.tables.sort.each do |table|
  next unless DB.table_exists?(table)
  before = SRC.select_value("select count(*) from #{SRC.quote_table_name(table)}").to_i
  after = DB.select_value("select count(*) from #{DB.quote_table_name(table)}").to_i
  next if before == after
  ok = table.match?(expected_changes)
  check "#{table} #{before} -> #{after}", ok, ok ? "personas, placeholders or cleared data" : "unexpected"
end

# --- Personas and logins ---------------------------------------------------------------
puts "== Personas"
PERSONA_EMAILS.each do |email|
  user = User.find_by(email: email)
  person = user&.person
  check "#{email} signs in with the demo password", user&.valid_password?(PASSWORD) && user.active_for_authentication?
  next unless person
  puts "      teams: #{person.memberships.includes(:team).map { "#{_1.team.name}#{' (manager)' if _1.manager}" }.join(', ')}"
  puts "      forms: #{FormResponse.where(subject: person).includes(:form).map { "#{_1.form.title} (#{_1.status})" }.join(', ')}"
  puts "      sign-ups: #{Signup.where(person: person).count}, badges: #{person.badges.count}"
end
PROTECT_EMAILS.each do |email|
  user = User.find_by("lower(email) = ?", email)
  check "#{email} can sign in (unchanged password, not locked)", user && user.active_for_authentication? && user.locked_at.nil?
end

# --- Password reset goes nowhere ---------------------------------------------------------
puts "== Password reset goes nowhere"
mailpit = ENV["MAILPIT_URL"].presence
Net::HTTP.start(URI(mailpit).host, URI(mailpit).port) { |http| http.delete("/api/v1/messages") } if mailpit
user = User.find_by!(email: PERSONA_EMAILS.first)
ActiveJob::Base.queue_adapter = :inline # what the worker would do, now
output = StringIO.new
$stdout = output
begin
  user.send_reset_password_instructions
ensure
  $stdout = STDOUT
end
check "the reset email for #{user.email} was only logged", output.string.include?("No email gateway configured")
if mailpit
  sleep 1
  check "nothing arrived in Mailpit", JSON.parse(Net::HTTP.get(URI("#{mailpit}/api/v1/messages")))["messages"].empty?
end
User.where(id: user.id).update_all(reset_password_token: nil, reset_password_sent_at: nil)

puts
if FAILURES.any?
  puts "#{FAILURES.size} check(s) failed"
  exit 1
end
puts "All checks passed"
