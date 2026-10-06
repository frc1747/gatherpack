# BL-008: Restrict Member Info: its own on/off switch, and managers only by default

| | |
|---|---|
| Kind | upstream feature (amends our `feature/person-fields`) |
| Priority | high |
| Status | waiting |
| Added | 2026-10-05 |
| Branch checked | `feature/person-fields` at `5b2700a` (in release `v0.0.0-hbr.6`) |
| Planned branch | none: this goes on `feature/person-fields` itself, which is still `wip` |
| Upstream issue / PR | belongs with issue [#489](https://github.com/GatherPack/gatherpack/issues/489) (person fields) |

## Summary

Corey asked for two things:

1. **Member Info should be its own feature,** switched on and off site-wide, separately from custom person fields.
2. **Members who are minors shouldn't be able to use it.** It's useful for managers, so managers should keep it.

**Why it's high priority:** Member Info is the bulk "people × fields" roster page. It's live in production today, because `feature_person_fields` is on and the branch is in `hbr.6`. Its policy lets any signed-in user open it. Each cell still follows the field's read level. But at the current production levels (Email, Gender and Shirt Size are `team`), a student can list every teammate's email, gender and shirt size in one table, and print it.

**Interim option:** turning `feature_person_fields` off hides the Member Info nav and blocks the page. It also hides custom fields everywhere, so it's a blunt tool. Production has no custom fields with values yet (as of 2026-10-04 only the 7 system fields exist), so that cost may be acceptable until this ships. That's Corey's call.

**What this does and doesn't solve:** restricting the page removes *bulk* lookup. A member can still open a teammate's profile and see whatever that field's read level allows. If the concern is minors seeing a field at all, the fix is that field's read level, for example Email set to `leaders` (Setup → Person Fields, or "Apply recommended privacy settings"). Note this in the spec, so nobody mistakes this change for field privacy.

## Where things are today (`feature/person-fields` at `5b2700a`)

- **Feature registration:** `config/initializers/features.rb`, about lines 101–112. The `:person_fields` feature ("Custom Person Fields", `default_enabled: false`) owns the "Member Info" nav item (`roster_person_fields_path`, People section, position 25).
- **Controller:** `app/controllers/person_fields_controller.rb`.
  - Line 15: `before_action :require_feature, only: %i[ new create roster ]`.
  - Lines 109–122: `roster` authorizes `PersonField, :roster?`, lists `policy(PersonField).readable_fields`, and builds rows from `readable_subjects_for(viewer)` intersected with `policy_scope(Person)`.
  - Lines 129–135: `feature_enabled?` and `require_feature` check `:person_fields`.
- **Policy:** `app/policies/person_field_policy.rb`, lines 26–30: `roster?` returns `true` ("Open to everyone; the page only lists fields the user can read for someone").
- **Spec drift:** `docs/person-fields-spec.md` §4.2 (about line 534) says `roster?` is `user.admin? || record.readable_subjects_for(person).exists?`. The code doesn't do that. §10.6 (about lines 993–1004) describes the page.
- **Nav items can't be hidden per user today:** `lib/gatherpack/feature.rb`, line 3 has `NavItem = Struct.new(:label, :path, :icon)`. `SetupItem` (line 4) has a `policy_check`, which `app/helpers/nav_helper.rb` lines 27–28 honour. `lib/gatherpack/features.rb`, `nav_sections` (about lines 40–50), filters only on `enabled?`. So a restricted page would still show in the nav for people who can't open it.
- **Field list without custom fields:** `PersonField.in_use` returns only system fields when `:person_fields` is off. So Member Info works with custom fields off, which is useful once it's a separate feature.
- **"Manager":** `Person#manager?` (`app/models/person.rb`, about line 50) means admin, or a manager of at least one team.
- **Age:** age-based rules hinge on `Relationship.guardianship_age_limit` (`Settings[:guardianship_age_limit]`) and birthdays. In production the limit is blank and no birthdays are filled in (as of 2026-10-04). Age can't be the gate today.

## Proposed design

### 1. A separate `member_info` feature

- Register a new built-in feature in `config/initializers/features.rb`: key `:member_info`, label "Member Info", description "A printable table of selected person fields across many members", `default_enabled: false`, People section, position 25. Move the nav item from `:person_fields` to it.
- In `PersonFieldsController`, `roster` checks `:member_info` (its own `before_action`), and `:person_fields` keeps gating `new` and `create`. With custom fields off, the page lists system fields only (`in_use` already does this).
- The flag is stored as `feature_member_info` in `Settings`, like every other feature, and shows on the existing feature toggles screen.
- **Production rollout:** the new feature defaults to off, so shipping it hides Member Info until an admin turns it on. That's the safe default, but call it out in the release notes.

### 2. Who can open it

- A new setting, **"Member Info access"**, in the People group of `lib/settings.rb`. It's a select with these choices:
  - `admins`: admins only.
  - `managers` **(default)**: admins plus anyone who manages at least one team (`Person#manager?`).
  - `members`: every signed-in member (today's behaviour).
- `PersonFieldPolicy#roster?` becomes: feature on, **and** the viewer passes the access setting. Cells stay limited by each field's read level (`readable_subjects_for`), so a manager still only sees fields and people they could already see on profiles.
- Fix the spec drift while there. Pick one rule for §4.2 and make the code and spec agree: the access setting, plus "has at least one readable field" as now.
- **Hide the nav item from people who can't open it:** add an optional `policy_check` to `NavItem` (mirroring `SetupItem`), and have the nav render through the same `nav_helper` check. This is a small generic seam in upstream files (`lib/gatherpack/feature.rb`, `lib/gatherpack/features.rb` or the nav partial, `app/helpers/nav_helper.rb`), and it's worth offering upstream on its own (see the strategy notes).

### 3. Minors

The managers default covers Corey's concern without needing birthdays. Two optional extras to decide when this is picked up:

- **Badge-based access:** let admins also grant access by badge, for example a "Student Leadership" or "Health Officer" badge. This reuses the badge-grant pattern from `person_field_badge_grants` (a list of badge ids in a setting, or a join table). Skip it unless someone asks: managers plus admins may be enough.
- **Age cutoff:** "never people under the guardianship age limit, even if they manage a team". Only meaningful once birthdays and `guardianship_age_limit` are filled in. If added, people with no birthday should count as *not* old enough (fail closed), and the setting should say so.

## Open questions for Corey (decide before building)

1. Is the default access level `managers` right, or should it be `admins` only?
2. Should anyone besides managers (student leads, a health officer) get access through a badge?
3. Is an age cutoff wanted later? It needs birthdays filled in.
4. Interim: turn `feature_person_fields` off in production until this ships, or live with the current exposure?
5. Should Member Info be available when custom fields are off? The design above says yes (system fields only).

## Hooks

No hook changes. The access check and the feature flag don't create, update or destroy records, so no `CanBeHooked` callbacks or catalog entries are involved. Feature toggles and settings are stored in `Settings` (PStore), which isn't hooked. Nothing in the hook catalog (spec §8.1) needs a new event.

## Tests

- `PersonFieldPolicy#roster?`:
  - Each access level × admin, team manager, plain member.
  - The feature off blocks everyone, including admins: the page redirects, as `require_feature` does today.
- `PersonFieldsControllerTest#roster`:
  - A member gets a redirect (or 403) under `managers`.
  - A manager gets the table, and cells still honour `readable_subjects_for`.
  - Works with `:person_fields` off (system fields only).
- Nav:
  - The "Member Info" item is absent for a plain member under `managers`, and present for a manager.
  - `SetupItem` behaviour is unchanged.
- Feature registry: `member_info` appears on the toggles screen, defaults to off, and `nav_sections` respects it.

## Fork strategy notes

- **Where the work goes:** on `feature/person-fields` (status `wip`, not yet sent upstream), not a new branch. It's part of the same feature, and upstream should receive Member Info with sensible access control from the start. Update `docs/person-fields-spec.md` §4.2, §10.6 and the feature-registration section, plus the branch's `FORK.md` row: add `feature_member_info` to Flag and the new upstream files to "Upstream files touched".
- **The `NavItem` `policy_check` seam is generic:** any feature with a restricted page needs it. Per STRATEGY.md ("propose seams before features"), it could go to upstream as its own small PR on its own branch (for example `feature/nav-item-policy-check`), with `feature/person-fields` depending on it. Decide when picking this up. Keeping it inside person-fields is simpler if upstream is going to review person-fields as a whole anyway.
- No migration: the flag and the access setting both live in `Settings`.
- After the rebuild, test on Ditto (`ditto.hbrlive.com`) as a student, a team manager and an admin before tagging a release.
