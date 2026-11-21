# BL-077: Duplicate, everywhere a thing is set up again

Groups rerun the same things every season: sign-up sheets, events, commitments, orders. Forms have **Duplicate**; checklists and intake registrations have **Copy**; nothing else does, so people rebuild them by hand.

## Evidence

- Forms: `post :duplicate`, `Form#duplicate!` (`app/models/form.rb:342`), button in the action row (not in More).
- Checklists: `Checklists::Copier`, "Copy" in More (`checklists/show.html.erb:42`) and a copy form.
- Intake registrations: `Registration#copy` (`app/models/intake/registration.rb:128`), "Copy" in More, opens a prefilled New form.
- Sign-up sheets, events, commitments, order requests and inventory items have no copy.

## Fix

One word, one place: **Duplicate**, an item in **More** (before Archive/Restore and Delete), on every record below. It creates or prefills a new record named "<name> (copy)" and opens its Edit page so dates and names can be changed. Activity (answers, sign-ups, check-ins, progress, stock) is never copied.

| Record | Branch | Copies | Leaves behind | How |
|---|---|---|---|---|
| Form | `feature/forms` | as today | as today | move the button into More |
| Checklist | `feature/checklists` | as today | as today | rename Copy to Duplicate (button, copy page title and submit) |
| Intake registration | `feature/intake` | as today | as today | rename Copy to Duplicate |
| Sign-up sheet | `feature/signups` | sheet fields, positions with their rules, audience rules, organizers; not taking sign-ups | linked events, slots, sign-ups | `SignupSheets::Duplicator`, `post :duplicate`, opens Edit |
| Event | new `feature/event-duplicate` | type, team, name, location, description, times, check-in limit, lock, time clock period | check-ins and answers, sign-up links | `get :duplicate` renders New prefilled (as intake does), so the date is chosen before saving |
| Commitment | `feature/commitments` | fields, badges, organizers, sources in order | adjustments | `Commitments::Duplicator`, `post :duplicate`, opens Edit |
| Order request | `feature/orders` | team, funding source, lines (item, vendor, quantity, price, notes), as a draft by the person duplicating | approvals, watchers, purchases, history | `post :duplicate`, opens the draft; label **Duplicate** |
| Inventory item | `feature/inventory` | name, category, units, reorder settings, sources, reading types | stock levels, movements, units | `post :duplicate`, opens Edit |

Permission: the same as creating that thing (`new?`/`create?` on its policy), plus being able to see the original.

Event duplicate is an upstream edit: one route, one controller action and a `screen_action` in the `feature/record-footers` footer (shown only under `feature_screen_standard`; gated by its own flag `feature_event_duplicate`, default off).

## Tests

Per record: model/service test for what is copied and left behind; controller test for permission and redirect; view assertion that Duplicate sits in More.

## Fork notes

gphelp: mention Duplicate on each area's page.
