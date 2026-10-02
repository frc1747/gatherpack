# Spec: User-Defined Person Fields with Read/Write Permissions

Status: **Draft / proposal** — not yet implemented. Assumes the
authorization-hardening change (enforcing `authorize` on People, Events,
Checkins, and Relationships, and admin-gating the privileged `Person`
parameters) is merged; this design builds on it.
Date: 2026-09-27

## 1. Goal

Let administrators define extra fields on `Person` records (e.g. "Medical
notes", "Emergency contact", "Photo release on file", "Food allergies") without
code changes, and control **per field** who can read and who can write each
value.

The motivating case:

- A student member's guardian has provided sensitive information that mentors 
  but should not be broadcast to the entire team, and should be limited in scope,
  across mentors and adult volunteers based on a need-to-know basis.
- The people responsible for that student: their parents/guardians and the
  leaders of their team need to see it.
- Other students, other parents, and leaders with no responsibility for that
  student must **not** see it. The value must not leak through search, sorting,
  the calendar, the API, print sheets, or the logs either.

---

## 2. What exists today (and what we reuse)

### 2.1 Events: the EAV precedent we clone

Events already have a user-defined-fields system. We copy its shape wholesale:

| Piece | File | Role |
|---|---|---|
| `EventType has_many :checkin_fields` | `app/models/event_type.rb` | Field definitions, scoped to a type |
| `CheckinField` (`name`, `permission` enum) | `app/models/checkin_field.rb` | Definition |
| `CheckinFieldResponse` (`checkin_id`, `checkin_field_id`, `response :string`) | `app/models/checkin_field_response.rb` | Value (EAV row), plaintext string |
| `Checkin#refresh_fields` | `app/models/checkin.rb` | Materializes value rows to match the definitions |
| `CheckinFieldResponse#permission_check` | same | `case` on the enum deciding who may set the value |

`PersonField` / `PersonFieldValue` mirror this one-to-one. The **one** thing
`CheckinField` lacks that person data needs is a **read** permission:
`CheckinField#permission` only governs who may *write* a response;
`checkins/show`, `events#arrange`, and `events#print` show every response to
anyone who can open the page. For allergies that isn't acceptable, so
`PersonField` gets both a `read_permission` and a `write_permission` (§3.3).
That is the entire conceptual addition — everything else is a clone.

### 2.2 The permission patterns we build on

- **Enum + `permission_check` model method.** `CheckinFieldResponse` and
  `Relationship` both store an `added_by_*` enum and resolve it in a `case`
  with explicit escalation fallbacks (the manager branch also allows admins,
  etc.). `PersonField#readable_by?` / `#writable_by?` follow that form exactly.
- **A read-visibility ladder already exists:** `Page::PERMISSION_LEVELS =
  %w[public user team manager admin]`, stored as a `viewer`/`editor` string and
  validated with `inclusion`. `PersonField` uses the same shape, with audiences
  tuned to a person (§3.3).
- **Team tree helpers:** `Person#all_teams`, `Person#all_managed_teams`,
  `Team#all_managers_and_admins`, `Team#manager?(person)`.
- **Relationships:** `Person#relatives` already returns the people related to a
  person via any `Relationship`. That is the basis for the `family` audience.
- **Per-policy permitted params:** `TeamPolicy#permitted_attributes_for_update`
  is the precedent for varying strong params by role.

### 2.3 Prerequisites this design builds on

Field-level access control sits on top of the record-level controls. `authorize` is enforced on People, Events, Checkins, and Relationships,
and `PeopleController#person_params` restricts `user_id`, `team_ids`, and
`badge_ids` to admins.

Two record-level properties matter for hiding a field, and this feature
owns tightening them (part of §5 and §12, not separate cleanup):

- **Ransack exposure.** `Person.ransackable_attributes` lists
  `dietary_restrictions`, `address`, `phone_number`, and `birthday`, so
  `/people?q[dietary_restrictions_cont]=peanut` is an oracle even when the view
  hides the field. This feature makes `ransackable_attributes` respect the read
  level (§5).
- **People-directory scope.** `PersonPolicy::Scope` resolves through
  `all_teams` (ancestors included) and `Team#all_people` (descendants
  included), so under a single root team every member can see every other
  member's profile. How far to narrow this is an open question (§13); the
  field-level read checks hold regardless, but a tighter directory is the
  stronger posture.

---

## 3. Data model

Two new tables, plus an optional grouping table. No grants table.

```
person_field_groups ─┐ (optional: sections on the profile)
                     │
person_fields ───────┴──< person_field_values >── people
```

### 3.1 `person_fields` (definition), neat_id prefix `pfd`

| Column | Type | Notes |
|---|---|---|
| `name` | string, required | Label shown in the UI |
| `key` | string, required, unique, `\A[a-z][a-z0-9_]*\z` | Stable identifier for Hooks, Reports, imports |
| `data_type` | integer enum | `string`, `text`, `boolean`, `date`, `integer`, `select`, `multi_select`, `phone`, `email` |
| `options` | jsonb | Choices for `select`/`multi_select`, plus validation (min, max, regex) |
| `help_text` | text | |
| `read_permission` | integer enum | Who may **see** the value (§3.3). Default `admin` |
| `write_permission` | integer enum | Who may **set** the value (§3.3). Default `managers` |
| `team_id` | uuid, nullable | **Applicability.** When set, the field applies only to people in this team's subtree (e.g. "Students"). Null = everyone |
| `person_field_group_id` | uuid, nullable | Profile section |
| `position` | integer | Ordering |
| `required` | boolean | Enforced only when the editor is allowed to write the field |
| `archived_at` | datetime | Soft delete. Hidden from forms, values kept |
| `system_column` | string, nullable | For built-in columns (§6). Never user-editable |

`read_permission` and `write_permission` both draw from the same enum, exactly
as `Page` has `viewer` and `editor` from one list.

### 3.2 `person_field_values` (value), prefix `pfv`

| Column | Type | Notes |
|---|---|---|
| `person_id` | uuid, FK, required | |
| `person_field_id` | uuid, FK, required | |
| `value` | text | JSON-encoded typed value (§7). **Plaintext**, like `CheckinFieldResponse#response` |
| `updated_by_id` | uuid → people, nullable | Who last wrote the value; shown in the UI |
| | | Unique index on `(person_id, person_field_id)` |

Values are materialized to match the definitions the same way
`Checkin#refresh_fields` does — a `Person#refresh_fields` builds the missing
rows and drops rows for archived/removed fields. (If the row count ever becomes
a concern, switching to on-write-only creation is a later optimization; match
the precedent first.)

### 3.3 Read and write permission levels

Both columns use one enum. Admins always pass. Each level is a named audience
resolved in a `case`, with the same escalation-fallback style as
`Relationship#permission_check`:

| Level | Who it grants (plus admins, always) |
|---|---|
| `admin` | admins only |
| `self` | the subject (the person the value is about) |
| `family` | the subject, their relatives (`subject.relatives`), **and** the managers of the subject's teams — "the people responsible for this person" |
| `managers` | the managers of the subject's teams and their ancestors (`viewer.all_managed_teams ∩ subject.all_teams`) |
| `team` | members of the subject's teams, plus everyone `family`/`managers` covers |
| `authenticated` | any signed-in user |

For the motivating case, **allergies = read `family`, write `family`**: the
child's parents and their team leaders (and admins) can see and edit it; other
parents, other kids, and unrelated leaders cannot. One level expresses the
whole requirement.

**The deliberate limitation.** This cannot express "only the *YPT-certified*
managers." `family`/`managers` grants *all* the responsible leaders, not a
badge-filtered subset. That refinement (require a `Badge` on top of a level) is
a possible later addition, tracked in §13. It is left out on purpose to keep
the model a single enum rather than an access-rule engine; "all the team's
leaders can see an allergy" is an acceptable v1.

**One dependency to flag.** `family` trusts the relationship graph, and
`team`/`managers` trust team membership. Those are only as trustworthy as the
rules for *creating* relationships and memberships. If a sensitive field uses
`family`, the `RelationshipType`s in play should be ones only admins/managers
can create (`permission: added_by_admin`/`added_by_manager`) — otherwise a
member who can self-declare "Parent of" a child could read that child's data.
This is a property of relationship creation, not of this feature, but it's a
precondition for using `family` on sensitive fields.

The model method:

```ruby
class PersonField < ApplicationRecord
  PERMISSION_LEVELS = %w[ admin self family managers team authenticated ].freeze
  enum :read_permission,  PERMISSION_LEVELS   # integer-backed, mapped by index
  enum :write_permission, PERMISSION_LEVELS

  def readable_by?(viewer, subject) = allows?(read_permission,  viewer, subject)
  def writable_by?(viewer, subject) = allows?(write_permission, viewer, subject)

  private

  def allows?(level, viewer, subject)
    return true if viewer&.admin?
    case level
    when "admin"         then false
    when "self"          then viewer == subject
    when "family"        then viewer == subject || subject.relatives.include?(viewer) || responsible?(viewer, subject)
    when "managers"      then responsible?(viewer, subject)
    when "team"          then (viewer.all_teams & subject.all_teams).any? || subject.relatives.include?(viewer) || responsible?(viewer, subject)
    when "authenticated" then true
    end
  end

  def responsible?(viewer, subject)
    (viewer.all_managed_teams & subject.all_teams).any?
  end
end
```

**Exposure rules derived from the level.** A field whose `read_permission` is
tighter than `authenticated` (i.e. anything other than `authenticated`) is
automatically:

- excluded from `Person.ransackable_attributes` (never searchable), and
- excluded from the API (`Api::V1::UserInfoController`), and
- added to `filter_parameters`.

That removes the need for a separate sensitivity classification — the read
level is the single axis.

### 3.4 `person_field_groups` (optional), prefix `pfgr`

`name`, `position`. Purely presentational — sections on the profile and the
edit form. No behavior.

---

## 4. Access evaluation

### 4.1 No service object — methods on the models

`PersonField#readable_by?` / `#writable_by?` (above) are the whole evaluator.
Convenience readers on `Person`, matching the fat-model style already in that
class:

```ruby
class Person
  def readable_fields_for(viewer)
    PersonField.active.applicable_to(self).select { |f| f.readable_by?(viewer, self) }
  end

  def writable_fields_for(viewer)
    PersonField.active.applicable_to(self).select { |f| f.writable_by?(viewer, self) }
  end
end
```

`applicable_to(person)` filters on the field's `team_id` (null, or the person
is in that subtree). For the profile page and edit form these run over a
person's handful of fields — no query fan-out. For list pages that show a field
across many people (a roster, a print sheet), resolve the level to a `Person`
scope once instead of per row; `managers`/`team` map to team-membership joins
we already build elsewhere.

### 4.2 Pundit integration

No per-field policy. Extend `PersonPolicy`:

```ruby
def readable_person_fields = record.readable_fields_for(person)
def writable_person_fields = record.writable_fields_for(person)

def permitted_attributes
  base = [ :first_name, :last_name, :display_name, :avatar, :bio ]
  base += [ :user_id, team_ids: [], badge_ids: [] ] if user.admin?  # admin-only, matching person_params today
  base + [ person_field_values: writable_person_fields.map(&:key) ]
end
```

`PersonFieldPolicy` and `PersonFieldGroupPolicy` inherit from **`AdminPolicy`**,
like `CheckinFieldPolicy`. (The custom scaffold generator produces a permissive
policy per AGENTS.md, so this is a hand edit after generating.)

### 4.3 Where enforcement lives

Reads are enforced in the **views and serializers** (they ask
`readable_person_fields`). The model does **not** hide values from trusted
callers — Hooks, Reports, jobs, and the console run without a viewer, exactly
as they already read `person.dietary_restrictions` today. That matches how
`Report#code` and `Page#dynamic` are trusted (admin/architect only).

Writes are enforced twice, cheaply: strong params only permit
`writable_person_fields`, and `PersonFieldValue#permission_check` (a clone of
`CheckinFieldResponse#permission_check`, using `writable_by?`) rejects a
disallowed write with a validation error instead of silently reverting it.

---

## 5. Every read path must be covered

The practical definition of "doesn't leak." Each row needs a test (§11).

| Surface | Change |
|---|---|
| `people/show.html.erb` | Replace the hard-coded `<p><b>Dietary Restrictions…` block with `render "people/fields", person: @person`, iterating `policy(@person).readable_person_fields` grouped by `person_field_group` |
| `people/_form.html.erb` | Render inputs only for `writable_person_fields`; show readable-but-not-writable values as read-only text |
| `PeopleController#person_params` | Use `permitted_attributes(@person)` (§4.2) |
| **Ransack** (`Person`, `Membership`) | `ransackable_attributes(auth_object)` returns only fields whose read level is `authenticated`, plus non-sensitive base columns. `birthday` (needed for "Sort by Age") allowed only for admins, or replaced with an `age_bucket` scope. Pass `auth_object: current_user` at every `Person.ransack` call (`people#index`, `search#*`, `calendar#calendar`). `person_field_values` is never ransackable |
| `CalendarController` birthdays | Filter `@birthdays` to subjects whose `birthday` is readable by the viewer |
| `SearchController#combo` | Already exposes only `identifier_name`; add a regression test so it stays that way |
| `Api::V1::UserInfoController` | No custom fields in v1; only base profile claims. A later `profile_fields` scope could expose `authenticated`-level fields |
| Events `print` / `arrange`, `checkins/show` | See §9 |
| Hooks (`CanBeHooked`) | Include in `PersonFieldValue` so `person_field_values - update` hooks fire; add to `Hook.catalog`. Hook code is architect-trusted |
| Logs | Add `person_field_values` and the sensitive base columns to `filter_parameters` |
| Turbo/fragment caching | None today. If added, cache keys must include the viewer's access fingerprint |
| Error pages / flash | Never interpolate field values into flash messages |

---

## 6. Bringing the built-in columns under the same control

`people` has `dietary_restrictions`, `birthday`, `address`, `phone_number`,
`gender`, and `shirt_size`. Represent each as a **system field**: seed one
`person_fields` row per column with `system_column` set (e.g.
`system_column: "dietary_restrictions"`). The read/write checks and the views
treat them like any other field, but the accessor reads/writes the column
instead of a `person_field_values` row.

- No data migration, and no change to Hooks/Reports that call
  `person.dietary_restrictions`.
- Admins set the read/write level for built-ins in the same UI.
- `system_column` fields can't be deleted; their `key` and `data_type` are
  fixed.
- Seeded levels: `dietary_restrictions` → read/write `family`; `address`,
  `phone_number`, `birthday` → read `family`, write `managers`; `gender`,
  `shirt_size` → read `team`, write `managers`.

Moving a column's data into `person_field_values` (and dropping the column) is
possible later for uniformity, but there's no encryption reason to rush it (§7),
so it stays optional.

---

## 7. Storage and types

- `value` is text holding a JSON-encoded typed value (`"true"`,
  `"\"2026-01-02\""`, `["peanut","shellfish"]`). `PersonField#cast(raw)` and
  `#serialize(input)` convert per `data_type` and validate against `options`.
- **Plaintext**, like `CheckinFieldResponse#response`. That is consistent with
  how the app stores every other string today, and it keeps Hooks, Reports, and
  the console working unchanged.

**Deferred: confidential-at-rest.** Encrypting a field so that even a DB dump
or the audit log can't reveal it is a *separate* decision, not part of this
feature, because the app's current trust model would undercut it: an architect
can read any value through a `Report` (`eval`), Hooks fire on changes, and
PaperTrail records edits. Per-field encryption without also constraining
Reports, Hooks, and backups would be a guarantee the system doesn't actually
honor. If a deployment genuinely needs it, it should be raised as its own change
that addresses those paths together — and it can be added to `PersonFieldValue`
later without reshaping this design.

---

## 8. Auditing

- `PersonField` and `PersonFieldGroup` get
  `has_paper_trail versions: { class_name: "AuditLog" }` like every other model;
  changing a field's read level is security-relevant and should be auditable.
- `PersonFieldValue` gets `has_paper_trail` too, recording values the same way
  `CheckinFieldResponse` does — no special redaction, because there is no
  confidential tier in v1 (§7).
- **Deferred:** logging *reads* ("who viewed this allergy") is a nice-to-have
  that belongs with the confidential-at-rest decision, not v1.

---

## 9. Integration with Events (optional, later phase)

Organizers often want allergies on a campout check-in sheet. Rather than copy
the value into a `CheckinFieldResponse` (no read control, and a stale copy),
add a nullable `checkin_fields.person_field_id`:

- A check-in field linked to a person field is **read-only and computed**; it
  shows the person's current value.
- `events#print`, `events#arrange`, and `checkins/show` show it only for
  subjects where `person_field.readable_by?(current_user.person, subject)` is
  true, and "—" otherwise.
- Relies on the Events and Checkins authorization that this design builds on.

The same phase should give plain `CheckinField` a read level too (reuse
`PersonField::PERMISSION_LEVELS`), since responses like "medication given at
3pm" have the same exposure problem.

---

## 10. Admin UX

- **Setup → People fields** — a `GatherPack::Feature` (`feature_person_fields`),
  toggleable, with a `setup_items` entry, matching how other features register.
- The field editor is an ordinary scaffold form with two dropdowns —
  **Who can see this** (`read_permission`) and **Who can edit this**
  (`write_permission`) — exactly like `Page`'s viewer/editor selects.
- **"Preview as…"**: pick a viewer and a subject and see which fields show.
  Cheap, because it just calls `readable_fields_for`. The best guard against a
  misconfiguration.

---

## 11. Testing strategy

The suite is mostly unrun scaffold output (AGENTS.md); this feature must not
follow that. Minimum:

1. **`readable_by?` / `writable_by?` unit tests**
   (`test/models/person_field_test.rb`): a fixture world of Org → Pack → team A /
   team B; a student in team A, their parent, another team A student and *their*
   parent, a team A leader, a team B leader, an admin. Assert the full read/write
   matrix for a `family`-level field and a `team`-level field.
2. **Leak tests** (integration): for each surface in §5, sign in as "other
   parent" and assert the allergy value never appears — include
   `GET /people?q[dietary_restrictions_cont]=…`, the calendar JSON,
   `search/combo`, and the API `userinfo` endpoint.
3. **Write tests:** a crafted `PATCH /people/:id` with a `person_field_values`
   the viewer can't write is dropped by strong params and rejected by
   `PersonFieldValue#permission_check`.

Add these to CI's `test` job; consider returning `test` to `publish`'s `needs`
once this slice is green (AGENTS.md).

---

## 12. Rollout plan

| Phase | Scope | Breaks anything? |
|---|---|---|
| **0: Read-surface prep** | Make `Person`/`Membership` `ransackable_attributes` respect field read levels; add `verify_authorized`/`verify_policy_scoped` to `InternalController`; decide the people-directory scope (§13), behind a setting if orgs rely on "everyone sees everyone" | Tightening Ransack and the directory changes what non-admins can search and see — note it in release notes |
| **1: Model + UI** | `PersonField`, `PersonFieldValue`, `PersonFieldGroup` (scaffold + generator), the `readable_by?`/`writable_by?` methods, `Person#refresh_fields`, admin CRUD, "Preview as…" | No. Feature flag off by default |
| **2: System fields** | Seed the built-in columns as system fields (§6); switch `people/show`, `_form`, Ransack, calendar, and strong params to the field API | Built-in fields become hidden from people who used to see them — the intended result; announce it |
| **3: Events integration** | §9, plus a read level on `CheckinField` | No |
| **4: Later, if wanted** | Badge-refined levels (§13), moving columns into the value table, confidential-at-rest (§7), read-access logging | No |

Migrations in phases 1–3 touch the **primary** DB only. Per AGENTS.md, run both
`db:migrate:primary` and `db:migrate:versions` even so (the audit DB is separate).

---

## 13. Open questions

1. **Badge-refined levels.** Is "all the team's leaders can see an allergy" good
   enough, or is "only YPT-certified leaders" a hard requirement? If the latter,
   add an optional `required_badge_id` on `PersonField` that ANDs with
   `managers`/`family`. That's the one sanctioned step toward the richer model,
   taken only when a real field needs it.
2. **Should `self` read apply to young children?** A parent may want a field
   the child can't see. `read_permission: family` already covers "parent yes,
   others no"; whether the subject themselves is included is the question. Could
   become a per-field `include_self` flag.
3. **People-directory scope.** `PersonPolicy::Scope` returns everyone within a
   shared team tree; the field checks hold regardless, but a narrower default is
   the stronger posture. What should it be?
4. **Is "leader" always a team manager**, or does the org need a non-manager
   "assistant leader" role? If so, a `Membership#role` enum beats overloading
   badges.
5. **Transitive family?** `family` uses `Person#relatives` (direct edges only).
   Grandparent-via-parent is intentionally excluded; confirm that's desired.
