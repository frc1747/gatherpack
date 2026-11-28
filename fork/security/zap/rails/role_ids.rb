# Read-only: each ZAP scan login's own person id, wards and managed people,
# as one JSON line (ROLEIDS {...}) for the kit's crossrole.py (--ids).
# Staging copies only. Run with bin/rails runner (campaign.sh does).
# Refuses to run in the production Rails environment unless
# SCAN_ALLOW_PRODUCTION_ENV=1 (staging copies run it; the kit's runner sets it).
# ENV: SCAN_ROLES (default student parent mentor student2 architect),
#      SCAN_EMAIL_PATTERN (printf pattern, default zap.%s@example.invalid).
require "json"

if Rails.env.production? && ENV["SCAN_ALLOW_PRODUCTION_ENV"] != "1"
  abort "Refusing to run in the production Rails environment. Staging copies run it: set SCAN_ALLOW_PRODUCTION_ENV=1 (the kit's runner command does)."
end

pattern = ENV.fetch("SCAN_EMAIL_PATTERN", "zap.%s@example.invalid")
out = {}
ENV.fetch("SCAN_ROLES", "student parent mentor student2 architect").split.each do |role|
  user = User.find_by(email: format(pattern, role)) or next
  p = user.person
  out[role] = {
    self: p.to_param,
    wards: p.wards.map(&:to_param),
    managed: p.all_managed_people.map(&:to_param),
    teams: p.all_teams.map(&:to_param)
  }
end
puts "ROLEIDS #{out.to_json}"
