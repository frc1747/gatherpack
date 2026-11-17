# Summaries (digests) spec

Status: seam built (task 317, hbr.46). Connected: inventory. Next: orders (buyers), intake (registrations).

## Goal
Features that send a person a regular summary can put it in one combined daily email per person, in the Weekly Infodump (upstream's announcements email, `infodump_day`/`infodump_time`), or both. A person only gets a section that has something for them.

## Use cases
| Who | Today | With summaries |
|---|---|---|
| Inventory manager | Running-low digest, its own email at 7:00 | A section in the daily email or the Weekly Infodump, chosen by Running Low Notices ("In the Weekly Infodump") |
| Buyer | Orders daily digest | Same, once connected |
| Team manager | Registrations waiting | Same, once connected |

## Design
- `GatherPack::Digests.register(key, label:, delivery: -> { :daily|:weekly|:both|:off }, build: ->(person, since:) { nil | Section })`, from the feature's initializer, guarded by `defined?(GatherPack::Digests)`.
- The choice lives on each feature's own setup page, in its existing notice setting. Nothing is added to the Settings page except the `feature_digests` flag.
- Daily: `DeliverDailyDigestsJob` every 15 minutes; sends once 7:00 has passed in the site time zone; covers 7:00 yesterday to now; one email per person ("Your <title> update"); at most once a day (`digest_deliveries`, unique per person and day, pruned after 60 days).
- Weekly: `Infodump#generate` calls `GatherPack::Digests.append_weekly(@content, @person)` after the announcements (last 7 days); the Infodump goes out if there were announcements or any section. Upstream's subject is unchanged.
- Flag `feature_digests`, default off: no daily email and nothing appended; features keep their own emails. A feature skips its own email while `GatherPack::Digests.handles?(key)`.
- Sent through `SendEmailJob` with `Gateway[:email_sending]`.

## Words on screen
"Summaries" (feature), "In the Weekly Infodump" (inventory's choice), subject "Your <site title> update".

## Hooks
None: a summary is an email, not a domain event; `DigestDelivery` is bookkeeping.

## Depends on
`feature/recurring-routes-seams` for `config/recurring.d/digests.yml`.
