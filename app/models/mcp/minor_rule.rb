# A minor's contact details never go through MCP, whoever is asking: admins,
# managers, guardians and the minor themself all get the same answer. The concern
# is the data reaching an AI client, not who may see it, so this is not a
# permission rule and the app's pages aren't affected. There is no setting for now;
# this file is the one place to change if that becomes configuration.
#
# One exception, an administrator's choice: a dynamic page's ERB can print these details
# by any route, so its output can't be filtered. get_page refuses dynamic pages unless
# mcp_dynamic_pages_enabled is on, and with it on they pass through as the page shows them.
#
# A person counts as a minor if they are under 18 today in the app's time zone,
# or their age is unknown: no birthday on file, or one more than 120 years ago,
# which nothing validates and a short year in a date field can produce. The app
# has no other marker of age, so an unknown age fails closed. They turn 18 on the
# birthday itself, and someone born on February 29 turns 18 on March 1 (18 years
# after a leap year is never one), the later of the two dates in use, again failing
# closed. The date is taken in the app's time zone whatever zone the caller is in.
#
# Callers leave WITHHELD_KEYS out rather than sending null, and give no reason per
# person: "minor" would reveal the age of someone with a birthday on file.
#
# Deliberately not an Mcp.person_filters entry: an empty list of filters means
# field rules have nothing to apply them (see GetPerson#field_rules_without_filter?),
# so a core entry would switch that off. Connector tools call
# Mcp.withhold_contact_details?.
module Mcp::MinorRule
  ADULT_AGE = 18
  MAX_BELIEVABLE_AGE = 120
  WITHHELD_KEYS = %w[email phone_number address birthday].freeze

  class << self
    def minor?(person)
      birthday = person.birthday
      return true if birthday.nil?

      today = Time.current.in_time_zone(Settings[:time_zone].presence || "UTC").to_date
      return true if birthday < today.prev_year(MAX_BELIEVABLE_AGE)

      age = today.year - birthday.year
      age -= 1 if ([ today.month, today.day ] <=> [ birthday.month, birthday.day ]).negative?
      age < ADULT_AGE
    end
  end
end
