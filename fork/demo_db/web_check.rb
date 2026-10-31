# Renders the dashboard, every Page and every Report in the demo database as
# each persona and each protected account listed in DEMO_PROTECT_EMAILS, in
# process (no password needed, nothing written). Exits non-zero if any
# request fails. Run by bin/fork-make-demo-db after verify.rb.
require_relative "guard"

DemoDb.guard!
include Warden::Test::Helpers
Warden.test_mode!

emails = %w[demo.member@example.invalid demo.lead@example.invalid demo.mentor@example.invalid] +
  ENV["DEMO_PROTECT_EMAILS"].to_s.split(",").map(&:strip).reject(&:empty?)
failures = 0

emails.each do |email|
  user = User.find_by("lower(email) = ?", email.downcase) || next
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! "localhost"
  login_as(user, scope: :user)
  puts "== #{email}#{' (admin)' if user.admin?}"
  paths = [ [ "dashboard", "/" ] ] + Page.order(:title).map { [ "page #{_1.title}", "/pages/#{_1.to_param}" ] }
  paths += Report.order(:name).map { [ "report #{_1.name}", "/reports/#{_1.to_param}/run" ] } if user.admin?
  paths.each do |label, path|
    session.get(path)
    body = session.response.body
    rows = body.scan(/<tr[\s>]/).size
    ok = session.response.status < 500
    failures += 1 unless ok
    status = session.response.status
    note = status == 404 ? "hidden from this account" : format("%6d bytes  %4d table rows", body.bytesize, rows)
    puts format("   [%s] %-40s %d  %s", ok ? "ok" : "FAIL", label, status, note)
  end
  Warden.test_reset!
end

# A plain exit here trips the runner's error reporter after in-process requests.
$stdout.flush
exit!(1) if failures.positive?
