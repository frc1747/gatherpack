# Creates the non-admin logins for authenticated ZAP scans (security kit):
#   student   - member of SCAN_TEAM_MEMBER, minor
#   parent    - member of SCAN_TEAM_GUARDIANS, guardian of the student
#   mentor    - member of SCAN_TEAM_MENTORS, manager of SCAN_TEAM_MEMBER (manages the student)
#   student2  - member of SCAN_TEAM_PEER (a peer the mentor does not manage)
#   architect - member of SCAN_TEAM_MENTORS, architect flag, manages nothing
#
# Staging copies only. Run with bin/rails runner (setup-accounts.sh does).
# Dry run (rolled back) unless COMMIT=1. Refuses to run in the production
# Rails environment unless SCAN_ALLOW_PRODUCTION_ENV=1 (staging copies run it;
# the kit's runner command sets it). Passwords are never printed.
#
# ENV: SCAN_PW_STUDENT, SCAN_PW_PARENT, SCAN_PW_MENTOR, SCAN_PW_STUDENT2,
#      SCAN_PW_ARCHITECT, SCAN_TEAM_MEMBER, SCAN_TEAM_GUARDIANS,
#      SCAN_TEAM_MENTORS, SCAN_TEAM_PEER, SCAN_ADMIN_EMAIL (an existing admin
#      login: the relationship is recorded as created by that person),
#      SCAN_EMAIL_PATTERN (printf pattern, default zap.%s@example.invalid),
#      COMMIT=1 to write.
if Rails.env.production? && ENV["SCAN_ALLOW_PRODUCTION_ENV"] != "1"
  abort "Refusing to run in the production Rails environment. Staging copies run it: set SCAN_ALLOW_PRODUCTION_ENV=1 (the kit's runner command does)."
end

commit = ENV["COMMIT"] == "1"
roles = %w[student parent mentor student2 architect]
pattern = ENV.fetch("SCAN_EMAIL_PATTERN", "zap.%s@example.invalid")
pw = roles.to_h { |r| [r, ENV.fetch("SCAN_PW_#{r.upcase}")] }
admin_user = User.find_by!(email: ENV.fetch("SCAN_ADMIN_EMAIL"))
admin_person = admin_user.person
raise "SCAN_ADMIN_EMAIL is not an admin" unless admin_user.admin?
PaperTrail.request.whodunnit = admin_user.id

def scan_say(label, value = nil)
  puts value.nil? ? label.to_s : format("%-40s %s", label, value)
end

scan_say "environment", "#{Rails.env} (#{ActiveRecord::Base.connection.current_database})"
scan_say "mode", commit ? "COMMIT" : "dry run"

member_team = Team.find_by!(name: ENV.fetch("SCAN_TEAM_MEMBER"))
guardians_team = Team.find_by!(name: ENV.fetch("SCAN_TEAM_GUARDIANS"))
mentors_team = Team.find_by!(name: ENV.fetch("SCAN_TEAM_MENTORS"))
peer_team = Team.find_by!(name: ENV.fetch("SCAN_TEAM_PEER"))
gtype = RelationshipType.where(guardianship: :minor).first or raise "no minor guardian type"

def scan_person(first, email, password, birthdate: nil, architect: false)
  user = User.find_or_initialize_by(email: email)
  # Only new logins get a password: changing it on an existing login ends
  # its sessions (Devise salt), which would sign out a scan in progress.
  user.password = password if user.new_record?
  user.admin = false
  user.architect = architect
  user.save!
  person = Person.find_by(user_id: user.id) || Person.new(user: user)
  person.first_name = first
  person.last_name = "Scan"
  person.birthday = birthdate if birthdate
  person.save!
  person
end

# The audit log is a separate database, so a rolled-back dry run would still
# leave its versions rows behind: dry runs don't record them.
paper_trail_was = PaperTrail.enabled?
PaperTrail.enabled = false unless commit
begin
  ActiveRecord::Base.transaction do
    student = scan_person("ZAP Student", format(pattern, "student"), pw.fetch("student"), birthdate: Date.new(2010, 6, 1))
    parent = scan_person("ZAP Parent", format(pattern, "parent"), pw.fetch("parent"))
    mentor = scan_person("ZAP Mentor", format(pattern, "mentor"), pw.fetch("mentor"))
    student2 = scan_person("ZAP Student2", format(pattern, "student2"), pw.fetch("student2"), birthdate: Date.new(2011, 3, 1))
    architect = scan_person("ZAP Architect", format(pattern, "architect"), pw.fetch("architect"), architect: true)
    Membership.find_or_create_by!(person: student2, team: peer_team)
    Membership.find_or_create_by!(person: architect, team: mentors_team)
    Membership.find_or_create_by!(person: student, team: member_team)
    Membership.find_or_create_by!(person: parent, team: guardians_team)
    Membership.find_or_create_by!(person: mentor, team: mentors_team)
    Membership.find_or_create_by!(person: mentor, team: member_team).update!(manager: true)
    Relationship.find_or_create_by!(parent: parent, child: student, relationship_type: gtype) { |r| r.created_by = admin_person }
    raise "student not minor-guarded" unless student.guardians.include?(parent)
    raise "mentor can't manage student" unless mentor.can_manage(student)
    raise "mentor manages student2" if mentor.can_manage(student2)
    raise "architect manages someone" if architect.manager?
    raise "admin leaked" if [student, parent, mentor, student2, architect].any?(&:admin?)
    [student, parent, mentor, student2, architect].each do |p|
      scan_say p.first_name, "#{p.user.email} teams=#{p.teams.pluck(:name).join('|')} manager=#{p.manager?}"
    end
    unless commit
      scan_say "DRY RUN: rolled back (pass COMMIT=1 to write)"
      raise ActiveRecord::Rollback
    end
  end
  scan_say "COMMITTED" if commit
ensure
  PaperTrail.enabled = paper_trail_was
end
