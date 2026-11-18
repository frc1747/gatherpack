# Anonymizes a restored production copy in place. Run by bin/fork-make-demo-db
# through `bin/rails runner` in a checkout of the release the dump came from.
# See fork/demo_db/README.md for what it changes.
#
# Env: DEMO_SEED (secret; the same seed gives the same fake people),
#      DEMO_PASSWORD, DEMO_PROTECT_TEAM, DEMO_PROTECT_EMAILS (comma separated),
#      DEMO_REPORT (where flagged text is listed).
require "openssl"
require "set"
require_relative "guard"
require_relative "names"

DemoDb.guard!
PaperTrail.enabled = false

SEED = ENV["DEMO_SEED"].presence || DemoDb.refuse("DEMO_SEED is not set")
PASSWORD = ENV["DEMO_PASSWORD"].presence || "password123"
PROTECT_TEAM = ENV["DEMO_PROTECT_TEAM"].presence || "Mentors"
PROTECT_EMAILS = ENV["DEMO_PROTECT_EMAILS"].to_s.split(",").map { |email| email.strip.downcase }.reject(&:empty?)
REPORT = ENV["DEMO_REPORT"].presence || "demo-db-flags.txt"
DB = ActiveRecord::Base.connection

def hmac(*parts)
  OpenSSL::HMAC.hexdigest("SHA256", SEED, parts.join("\u0000")).to_i(16)
end

def say(label, value = nil)
  puts value.nil? ? "== #{label}" : "   #{label}: #{value}"
end

FLAGS = []
def flag(where, reason, text = nil)
  FLAGS << [ where, reason, text && text.to_s.gsub(/\s+/, " ").first(160) ].compact.join(" | ")
end

# --- Who is protected ---------------------------------------------------------

say "Protected accounts"
team = Team.find_by(name: PROTECT_TEAM) || DemoDb.refuse("no team named #{PROTECT_TEAM.inspect}")
missing = PROTECT_EMAILS - User.where("lower(email) in (?)", PROTECT_EMAILS).pluck(:email).map(&:downcase)
DemoDb.refuse("protected emails not found: #{missing.join(', ')}") if missing.any?
protected_user_ids = User.where("lower(email) in (?)", PROTECT_EMAILS).pluck(:id)
PROTECTED = (Membership.where(team_id: team.id).pluck(:person_id) | Person.where(user_id: protected_user_ids).pluck(:id)).to_set
protected_user_ids |= Person.where(id: PROTECTED.to_a).where.not(user_id: nil).pluck(:user_id)
say "#{PROTECT_TEAM} members + listed accounts (people)", PROTECTED.size
say "protected users", protected_user_ids.size

people = Person.order(:created_at, :id).to_a
others = people.reject { |person| PROTECTED.include?(person.id) }
words = ->(text) { text.to_s.scan(/[[:alpha:]][[:alpha:]'’-]*/) }
real_words = people.flat_map { |person| [ person.first_name, person.last_name ].flat_map(&words) + words.(person.display_name) }.map(&:downcase).to_set
protected_words = people.select { |person| PROTECTED.include?(person.id) }
  .flat_map { |person| [ person.first_name, person.last_name ].flat_map(&words) + words.(person.display_name) }.map(&:downcase).to_set
usable = ->(list) { list.reject { |name| real_words.include?(name.downcase) } }
FEMALE = usable.(DemoDb::FEMALE_FIRST)
MALE = usable.(DemoDb::MALE_FIRST)
ANY = (FEMALE + MALE).sort
LASTS = usable.(DemoDb::LAST)

# --- Fake identities ------------------------------------------------------------

say "Fake identities"
# A real surname always becomes the same fake surname, so families stay together.
surname_for = {}
DemoDb.refuse("more real surnames than fake ones; extend names.rb") if others.map { |person| person.last_name.to_s.squish.downcase }.uniq.size > LASTS.size
taken = Set.new
others.map { |person| person.last_name.to_s.squish.downcase }.uniq.reject(&:empty?).sort_by { |name| hmac("last", name) }.each do |name|
  index = hmac("last", name) % LASTS.size
  index = (index + 1) % LASTS.size while taken.include?(index)
  taken << index
  surname_for[name] = LASTS[index]
end

def first_list(gender)
  case gender.to_s.strip
  when /\A(m|male|man|boy)\z/i then MALE
  when /\A(f|female|woman|girl)\z/i then FEMALE
  else ANY
  end
end

IDENTITY = {}
full_names = Set.new
used_emails = User.where(id: protected_user_ids).pluck(:email).map(&:downcase).to_set
ascii = ->(name) { I18n.transliterate(name.to_s).downcase.gsub(/[^a-z]/, "") }

others.each do |person|
  last = surname_for[person.last_name.to_s.squish.downcase] || LASTS[hmac("last-blank", person.id) % LASTS.size]
  list = first_list(person.gender)
  attempt = 0
  first = nil
  loop do
    first = list[hmac("first", person.id, attempt) % list.size]
    break if full_names.add?("#{first} #{last}")
    attempt += 1
  end

  # Words of the real name (first, last, and any preferred name) to their fakes.
  word_map = {}
  words.(person.first_name).each_with_index { |word, i| word_map[word.downcase] ||= i.zero? ? first : list[hmac("first-extra", person.id, word.downcase) % list.size] }
  words.(person.last_name).each { |word| word_map[word.downcase] ||= last }
  words.(person.display_name).each { |word| word_map[word.downcase] ||= list[hmac("preferred", person.id, word.downcase) % list.size] }

  display = person.display_name.presence && person.display_name.gsub(/[[:alpha:]][[:alpha:]'’-]*/) { |word| word_map[word.downcase] || word }
  number = hmac("email", person.id) % 10_000
  email = nil
  loop do
    email = format("%s.%s.%04d@example.invalid", ascii.(first), ascii.(last), number)
    break unless used_emails.include?(email)
    number = (number + 1) % 10_000
  end
  used_emails << email

  IDENTITY[person.id] = { first: first, last: last, display: display, word_map: word_map, email: email }
end

# --- Phones, addresses, birthdays -------------------------------------------------

# 555-0100 through 555-0199 are reserved for fiction in every area code.
AREA_CODES = %w[317 765 812 219 260 574].freeze
phone_for = {}
phone_taken = Set.new
fake_phone_digits = lambda do |digits|
  phone_for[digits] ||= begin
    index = hmac("phone", digits) % (AREA_CODES.size * 100)
    index = (index + 1) % (AREA_CODES.size * 100) while phone_taken.include?(index)
    phone_taken << index
    format("%s55501%02d", AREA_CODES[index / 100], index % 100)
  end
end
# Same layout as the original, fake digits.
fake_phone = lambda do |original|
  digits = original.to_s.gsub(/\D/, "")
  core = digits.length == 11 && digits.start_with?("1") ? digits[1..] : digits
  return format("(%s) %s-%s", *fake_phone_digits.(digits).then { |d| [ d[0, 3], d[3, 3], d[6, 4] ] }) unless core.length == 10
  fake = fake_phone_digits.(core)
  fake = "1#{fake}" if core != digits
  i = -1
  original.gsub(/\d/) { fake[i += 1] }
end

street_for = {}
fake_address = lambda do |original|
  street, tail = original.to_s.split(",", 2)
  key = street.to_s.squish.downcase
  street_for[key] ||= format("%d %s %s", 100 + hmac("addr-n", key) % 9800,
    DemoDb::STREETS[hmac("addr-s", key) % DemoDb::STREETS.size], DemoDb::STREET_SUFFIXES[hmac("addr-x", key) % DemoDb::STREET_SUFFIXES.size])
  tail ? "#{street_for[key]},#{tail}" : street_for[key]
end

age_on = ->(birthday, day) { day.year - birthday.year - (day < birthday.next_year(day.year - birthday.year) ? 1 : 0) }
shift_birthday = lambda do |person|
  today = Date.current
  magnitude = 30 + hmac("birthday", person.id) % 151
  sign = hmac("birthday-sign", person.id).even? ? 1 : -1
  magnitude.downto(1).flat_map { |days| [ sign * days, -sign * days ] }
    .map { |days| person.birthday + days }
    .detect { |day| age_on.(day, today) == age_on.(person.birthday, today) } || person.birthday + sign
end

say "People"
counts = Hash.new(0)
real_phones = {}
real_emails = {}
others.each do |person|
  identity = IDENTITY[person.id]
  changes = { first_name: identity[:first], last_name: identity[:last], display_name: identity[:display], bio: nil }
  if person.phone_number.present?
    changes[:phone_number] = fake_phone.(person.phone_number)
    real_phones[person.phone_number.gsub(/\D/, "").last(10)] = changes[:phone_number]
    counts[:phones] += 1
  end
  if person.address.present?
    changes[:address] = fake_address.(person.address)
    counts[:addresses] += 1
    counts[:addresses_without_city] += 1 unless person.address.include?(",")
  end
  if person.birthday
    changes[:birthday] = shift_birthday.(person)
    counts[:birthdays] += 1
  end
  # Real dietary needs go; a seeded share of people get a made-up one.
  changes[:dietary_restrictions] = hmac("dietary", person.id) % 100 < 15 ? DemoDb::DIETARY[hmac("dietary-pick", person.id) % DemoDb::DIETARY.size] : nil
  counts[:dietary] += 1 if changes[:dietary_restrictions]
  Person.where(id: person.id).update_all(changes.merge(updated_at: person.updated_at))
end
say "people anonymized", others.size
counts.each { |key, value| say key, value }

# --- Users ------------------------------------------------------------------------

say "Users"
password_hash = User.new(password: PASSWORD).encrypted_password
person_by_user = others.select(&:user_id).group_by(&:user_id).transform_values(&:first)
User.where.not(id: protected_user_ids).find_each do |user|
  real_emails[user.email.downcase] = nil
  email = if (person = person_by_user[user.id])
    IDENTITY[person.id][:email]
  else
    number = hmac("user-email", user.id) % 10_000
    number = (number + 1) % 10_000 while used_emails.include?(format("user.%04d@example.invalid", number))
    format("user.%04d@example.invalid", number)
  end
  used_emails << email
  real_emails[user.email.downcase] = email
  User.where(id: user.id).update_all(email: email, encrypted_password: password_hash, provider: nil, uid: nil)
end
# Everyone, protected or not: no live sessions, reset links, lockouts or remember-me.
User.update_all(reset_password_token: nil, reset_password_sent_at: nil, remember_created_at: nil, locked_at: nil, failed_attempts: 0,
  session_token: Arel.sql("gen_random_uuid()::text"))
say "users anonymized", User.where.not(id: protected_user_ids).count
say "sessions and reset/remember tokens cleared", User.count

# --- Secrets, queues, outside connections -------------------------------------------

say "Secrets and outside connections"
DB.execute("delete from gateways")
DemoDb.refuse("gateways still has rows") unless DB.select_value("select count(*) from gateways").to_i.zero?
%w[oauth_access_tokens oauth_access_grants solid_cache_entries action_mailbox_inbound_emails].each { |table| DB.execute("delete from #{table}") }
DB.tables.grep(/\Asolid_queue_/).each { |table| DB.execute("truncate #{table} cascade") }
DB.execute("update oauth_applications set secret = md5(random()::text) || md5(random()::text), uid = md5(random()::text)")
say "gateways, OAuth tokens, queues, cache and inbound mail", "removed"
# No gateways at all, as on Ditto: GatherPack sends all mail, Devise's
# included, through a gateway, so every send is only logged.
external = /https?:|Net::HTTP|Faraday|HTTParty|URI|webhook|slack|discord/i
Hook.find_each do |hook|
  next unless hook.code.to_s.match?(external)
  Hook.where(id: hook.id).update_all(name: "[Disabled in demo] #{hook.name.delete_prefix('[Disabled in demo] ')}",
    code: "# Disabled in the demo copy: in production this hook calls an outside service.\nnil")
  say "hook disabled", hook.name
end

# Kiosk scan cards are credentials printed on real cards: new values for everyone.
token_taken = Token.pluck(:value).to_set
Token.where.not(tokenable_type: "Person").delete_all
Token.find_each do |token|
  prefix = token.value.to_s[/\A1747(?=\d{8}\z)/].to_s
  length = token.value.to_s.length - prefix.length
  attempt = 0
  value = nil
  loop do
    value = prefix + (hmac("token", token.id, attempt) % (10**length)).to_s.rjust(length, "0")
    break unless token_taken.include?(value)
    attempt += 1
  end
  token_taken << value
  Token.where(id: token.id).update_all(value: value)
end
say "kiosk tokens regenerated", Token.count

# --- Uploaded files -----------------------------------------------------------------

say "Uploaded files"
placeholder = begin
  require "vips"
  image = (Vips::Image.black(256, 256, bands: 3) + [ 226, 230, 234 ]).cast(:uchar)
  image = image.draw_circle([ 160, 168, 178 ], 128, 104, 52, fill: true)
  image = image.draw_circle([ 160, 168, 178 ], 128, 290, 110, fill: true)
  image.write_to_buffer(".png")
end
variant_blob_ids = ActiveStorage::Attachment.where(record_type: "ActiveStorage::VariantRecord").pluck(:blob_id)
ActiveStorage::Attachment.where(record_type: "ActiveStorage::VariantRecord").delete_all
ActiveStorage::VariantRecord.delete_all
ActiveStorage::Blob.where(id: variant_blob_ids).delete_all
replaced = Hash.new(0)
ActiveStorage::Attachment.where.not(record_type: "Theme").find_each do |attachment|
  old_blob_id = attachment.blob_id
  blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(placeholder), filename: "#{attachment.name.singularize}.png", content_type: "image/png")
  ActiveStorage::Attachment.where(id: attachment.id).update_all(blob_id: blob.id)
  ActiveStorage::Blob.where(id: old_blob_id).where.not(id: ActiveStorage::Attachment.select(:blob_id)).delete_all
  replaced["#{attachment.record_type}.#{attachment.name}"] += 1
end
replaced.each { |kind, count| say "#{kind} replaced with a placeholder", count }

# --- Free text ----------------------------------------------------------------------

say "Free text"
COMMON = File.exist?("/usr/share/dict/words") ? File.foreach("/usr/share/dict/words").map(&:chomp).select { |word| word.match?(/\A[a-z]+\z/) }.to_set : Set.new

PHRASES = {}
TOKENS = Hash.new { |hash, key| hash[key] = {} }
others.each do |person|
  identity = IDENTITY[person.id]
  first, last = person.first_name.to_s.squish, person.last_name.to_s.squish
  PHRASES["#{first} #{last}".downcase] ||= "#{identity[:first]} #{identity[:last]}" if first.present? && last.present?
  PHRASES["#{last}, #{first}".downcase] ||= "#{identity[:last]}, #{identity[:first]}" if first.present? && last.present?
  PHRASES[person.display_name.squish.downcase] ||= identity[:display] if person.display_name.present? && person.display_name.include?(" ")
  identity[:word_map].each { |word, fake| TOKENS[word][person.id] = fake if word.length >= 2 }
end
PHRASE_RX = PHRASES.empty? ? nil : /(?<![[:alpha:]])(#{PHRASES.keys.sort_by { -_1.length }.map { |phrase| Regexp.escape(phrase).gsub("\\ ") { "\\s+" } }.join('|')})(?![[:alpha:]])/i
EMAIL_RX = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
PHONE_RX = /(?<!\d)(?:\+?1[ .-]?)?\(?\d{3}\)?[ .-]?\d{3}[ .-]?\d{4}(?!\d)/
PROTECTED_EMAILS = User.where(id: protected_user_ids).pluck(:email).map(&:downcase).to_set
RELATIVES = Hash.new { |hash, key| hash[key] = Set[key] }
Relationship.pluck(:parent_id, :child_id).each do |parent, child|
  RELATIVES[parent] << child
  RELATIVES[child] << parent
end

def match_case(original, fake)
  return fake.upcase if original.length > 1 && original == original.upcase
  return fake.downcase if original == original.downcase
  fake
end

# Real names, emails and phones in text become their fake counterparts. Words
# shared with a protected person stay and are flagged; a word that could be
# several people takes the person the record is about, or is flagged.
scrub = lambda do |text, where:, context: []|
  return text unless text.is_a?(String) && !text.empty?
  family = context.flat_map { |id| RELATIVES[id].to_a }.to_set
  out = text.gsub(EMAIL_RX) do |email|
    if PROTECTED_EMAILS.include?(email.downcase) then email
    elsif (fake = real_emails[email.downcase]) then fake
    else
      flag(where, "unknown email address replaced")
      format("someone.%04d@example.invalid", hmac("unknown-email", email.downcase) % 10_000)
    end
  end
  out = out.gsub(PHONE_RX) do |phone|
    fake = real_phones[phone.gsub(/\D/, "").last(10)]
    flag(where, "phone number not on any profile replaced") unless fake
    fake || fake_phone.(phone)
  end
  out = out.gsub(PHRASE_RX) { |phrase| match_case(phrase, PHRASES[phrase.squish.downcase]) } if PHRASE_RX
  out.gsub(/[[:alpha:]][[:alpha:]'’-]*/) do |word|
    key = word.downcase
    candidates = TOKENS.key?(key) ? TOKENS[key] : nil
    next word unless candidates
    if protected_words.include?(key)
      flag(where, "word is also a protected person's name, left as is")
      next word
    end
    next word if COMMON.include?(key) && word == key # "will", "may", "grant" in ordinary use
    fakes = candidates.values.uniq
    chosen = if fakes.one? then fakes.first
    elsif (hit = candidates.keys.detect { |id| family.include?(id) }) then candidates[hit]
    else
      flag(where, "name matches #{fakes.size} people; picked one")
      candidates[candidates.keys.min]
    end
    match_case(word, chosen)
  end
end

def walk(value, &block)
  case value
  when String then block.call(value)
  when Array then value.map { |item| walk(item, &block) }
  when Hash then value.transform_values { |item| walk(item, &block) }
  else value
  end
end

# Structure that must not change; scanned and flagged only.
STRUCTURAL = {
  "teams" => :all, "team_types" => :all, "badges" => :all, "badge_types" => :all, "relationship_types" => :all,
  "event_types" => :all, "person_fields" => :all, "person_field_groups" => :all, "checkin_fields" => :all,
  "time_clock_periods" => :all, "budget_periods" => :all, "ledger_tags" => :all, "themes" => :all
}.freeze
SKIP_TABLES = %w[people users tokens form_signatures schema_migrations ar_internal_metadata gateways oauth_access_tokens oauth_access_grants
  oauth_applications action_mailbox_inbound_emails].freeze
SKIP_COLUMNS = /\A(key|color|icon|permission|model|scope|status|style_mode|placement|viewer|editor|kind|content_type|checksum|service_name|
  variation_digest|filename|[a-z_]*_type|event|data_type|system_source|unit|content_digest|ip_address|user_agent|secrets?)\z/x

option_strings = Set.new
FormQuestion.pluck(:options).each { |options| walk(options) { |string| option_strings << string } }
person_ids = people.map(&:id).to_set
subject_for_response = FormResponse.pluck(:id, :subject_id).to_h
valid_signatures = FormSignature.includes(:form_submission).select { |signature| signature.content_digest == signature.form_submission.content_digest }.map(&:id)

changed = Hash.new(0)
text_columns = DB.select_rows(<<~SQL)
  select table_name, column_name, data_type from information_schema.columns
  where table_schema = 'public' and data_type in ('text', 'character varying', 'jsonb') order by 1, 2
SQL
text_columns.group_by(&:first).each do |table, columns|
  next if SKIP_TABLES.include?(table) || table.start_with?("solid_", "active_storage_")
  columns = columns.reject { |_, column, _| SKIP_COLUMNS.match?(column) }
  next if columns.empty? || !DB.column_exists?(table, :id)
  uuid_columns = DB.columns(table).select { |column| column.sql_type == "uuid" && column.name != "id" }.map(&:name)
  select = ([ "id" ] + uuid_columns + columns.map { _2 }).map { |name| DB.quote_column_name(name) }.join(", ")
  DB.select_all("select #{select} from #{DB.quote_table_name(table)}").each do |row|
    context = uuid_columns.map { |name| row[name] }.select { |id| person_ids.include?(id) }
    context << subject_for_response[row["form_response_id"]] if row["form_response_id"]
    updates = {}
    columns.each do |_, column, type|
      raw = row[column]
      next if raw.nil?
      where = "#{table}.#{column} #{row['id']}"
      value = type == "jsonb" ? JSON.parse(raw) : raw
      scrubbed = if table == "form_submissions" && column == "content" || table == "form_questions" || table == "forms"
        walk(value) { |string| scrub.(string, where: where) }
      else
        walk(value) { |string| option_strings.include?(string) ? scrub.(string, where: where) : scrub.(string, where: where, context: context) }
      end
      next if scrubbed == value
      if STRUCTURAL.key?(table)
        flag(where, "names found in structure; left unchanged")
        next
      end
      updates[column] = type == "jsonb" ? "#{DB.quote(JSON.generate(scrubbed))}::jsonb" : DB.quote(scrubbed)
      changed["#{table}.#{column}"] += 1
    end
    if row.key?("answers") && table == "form_submissions"
      JSON.parse(row["answers"] || "{}").each_key do |key|
        flag("#{table}.answers #{row['id']}", "answer key contains a name") if words.(key.tr('_', ' ')).any? { |w| TOKENS.key?(w.downcase) && !COMMON.include?(w.downcase) }
      end
    end
    next if updates.empty?
    DB.execute("update #{DB.quote_table_name(table)} set #{updates.map { |column, sql| "#{DB.quote_column_name(column)} = #{sql}" }.join(', ')} where id = #{DB.quote(row['id'])}")
  end
end
changed.sort.each { |column, count| say "#{column} rows rewritten", count }

# --- Signatures -----------------------------------------------------------------------

say "Signatures"
FormSignature.includes(:form_submission).find_each do |signature|
  identity = IDENTITY[signature.signer_id]
  typed = identity ? "#{identity[:first]} #{identity[:last]}" : signature.typed_name
  changes = { typed_name: typed, ip_address: "192.0.2.#{1 + hmac('ip', signature.id) % 254}", user_agent: "Mozilla/5.0 (demo browser)" }
  changes[:content_digest] = signature.form_submission.reload.content_digest if valid_signatures.include?(signature.id)
  FormSignature.where(id: signature.id).update_all(changes)
end
say "signatures rewritten", FormSignature.count
say "signatures still matching their submission", FormSignature.includes(:form_submission).count { |s| s.content_digest == s.form_submission.content_digest }

File.write(REPORT, FLAGS.uniq.join("\n") + "\n")
File.chmod(0o600, REPORT)
say "flags written to #{REPORT}", FLAGS.uniq.size
FLAGS.map { |line| line.split(" | ")[1] }.tally.each { |reason, count| say reason, count }
