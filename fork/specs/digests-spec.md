# Summaries (digests) spec

Status: seam built (task 317, hbr.46); personal choice and "each" (task 330). Connected: inventory, orders. Next: intake (registrations).

## Goal
Features that send a person a regular summary can put it in one combined daily email per person, in the Weekly Infodump (upstream's announcements email, `infodump_day`/`infodump_time`), or both, or email each thing as it happens. The site sets a default per feature; each person can choose differently for themselves. A person only gets a section that has something for them.

## Use cases
| Who | Today | With summaries |
|---|---|---|
| Inventory manager | Running-low digest, its own email at 7:00 | A section in the daily email or the Weekly Infodump, chosen by Running Low Notices ("In the Weekly Infodump") |
| Buyer | Orders daily digest | Same, once connected |
| Team manager | Registrations waiting | Same, once connected |

## Design
- `GatherPack::Digests.register(key, label:, delivery: -> { :each|:daily|:weekly|:both|:off }, build: ->(person, since:) { nil | Section }, personal: true)`, from the feature's initializer, guarded by `defined?(GatherPack::Digests)`. `:each` = no section; the feature emails as things happen. The key names the feature (the page offers the section only while that feature is on).
- Personal choice: `notice_preferences` (`person_id`, `key`, `delivery` one of `each daily weekly off`; unique per person and key). `GatherPack::Digests.delivery_for(key, person)` = the person's row while Summaries is on and the section is personal, else the site's choice; features call it to decide who gets an email right away. The daily email and the Infodump pick sections per person with it. Person merge: the kept person's row wins; others move.
- Email notices page (`/email_notices`, signed in, Summaries on, at least one personal section of an enabled feature): a radio group per section; "Use the site's choice" deletes the row. Where the Notifications page takes other features' cards (`GatherPack::NotificationSections`, `feature/phone-notifications`), the choices are an **Email** card on that page instead, `/email_notices` and saving lead there, and nothing is added to the sidebar or profile. Without it, the page is linked from the person's own profile.
- The choice lives on each feature's own setup page, in its existing notice setting. Nothing is added to the Settings page except the `feature_digests` flag.
- Daily: `DeliverDailyDigestsJob` every 15 minutes; sends once 7:00 has passed in the site time zone; covers 7:00 yesterday to now; one email per person ("Your <title> update"); at most once a day (`digest_deliveries`, unique per person and day, pruned after 60 days).
- Weekly: `Infodump#generate` calls `GatherPack::Digests.append_weekly(@content, @person)` after the announcements (last 7 days); the Infodump goes out if there were announcements or any section. Upstream's subject is unchanged.
- Flag `feature_digests`, default off: no daily email, nothing appended, no Email notices page, and `delivery_for` gives the site's choice; features keep their own emails. A feature skips its own email while `GatherPack::Digests.handles?(key)`.
- Sent through `SendEmailJob` with `Gateway[:email_sending]`.

## Words on screen
"Summaries" (feature), subject "Your <site title> update". Choices: "An email each time", "In the daily digest", "In the Weekly Infodump", "Off", "Use the site's choice (<site's choice>)". Page "Email notices" (card "Email" on the Notifications page), directions "Choose how you hear about each feature. The daily digest comes once a day around 7:00; the Weekly Infodump is the weekly announcements email."

## Hooks
None: a summary is an email, not a domain event; `DigestDelivery` and `NoticePreference` are bookkeeping.

## Depends on
`feature/recurring-routes-seams` for `config/recurring.d/digests.yml`.
