# Spec: User-Defined Person Fields with Read/Write Permissions

Status: **Ready for implementation.** Assumes the authorization-hardening change
(enforcing `authorize` on People, Events, Checkins, and Relationships, and
admin-gating the privileged `Person` parameters) is merged; this design builds
on it.
Date: 2026-10-02 (rev. 2; supersedes 2026-09-27)

## 1. Goal

Let administrators define extra fields on `Person` records (e.g. "Medical
notes", "Emergency contact", "Photo release on file", "Food allergies") without
code changes, and control **per field** who can read and who can write each
value. Bring the existing built-in profile fields (dietary restrictions, phone,
address, birthday, gender, shirt size, email) under the same control.

The motivating case:

- A student's guardian has provided sensitive information (an allergy, a medical
  note). It should be visible on a need-to-know basis, not broadcast to the
  whole organization.
- The people responsible for that student need to see it: their
  parents/guardians, the leaders of their team, and specific designated roles
  (e.g. a health officer) who are not leaders of that team.
- Other students, other parents, and leaders with no responsibility for that
  student must **not** see it. The value must not leak through search, sorting,
  the calendar, the API, print sheets, or the logs either.

### 1.1 Non-goals (v1)

- **Narrowing the people directory.** `PersonPolicy::Scope` / `#show?` let
  anyone who shares a team tree see a profile. Field-level checks hold
  regardless of that; tightening record-level visibility is a separate change.
- **Confidential-at-rest encryption** and **read-access logging** (§7, §8).
- **Badge-refined narrowing** ("only YPT-certified leaders"), §13.1.
- **Bulk import/export** of field values. The roster page (§10.6) prints; CSV
  is not in v1.
- **Name, display name, bio, and avatar** stay outside the field system. They
  are always visible to anyone who can see the profile, as today.

---

## 2. What exists today (and what we reuse)

### 2.1 Events: the EAV precedent we clone

Events already have a user-defined-fields system. We copy its shape:

| Piece | File | Role |
|---|---|---|
| `EventType has_many :checkin_fields` | `app/models/event_type.rb` | Field definitions, scoped to a type |
| `CheckinField` (`name`, `permission` enum) | `app/models/checkin_field.rb` | Definition |
| `CheckinFieldResponse` (`checkin_id`, `checkin_field_id`, `response :string`) | `app/models/checkin_field_response.rb` | Value (EAV row), plaintext string |
| `Checkin#refresh_fields` | `app/models/checkin.rb` | Materializes value rows to match the definitions |
| `CheckinFieldResponse#permission_check` | same | `case` on the enum deciding who may set the value |

`PersonField` / `PersonFieldValue` mirror this. Two deliberate differences:

1. **A read permission.** `CheckinField#permission` only governs who may
   *write*; `checkins/show`, `events#arrange`, and `events#print` show every
   response to anyone who can open the page. `PersonField` gets both
   `read_permission` and `write_permission` (§3.3).
2. **Values are never deleted as a side effect.** `Checkin#refresh_fields`
   deletes responses whose field was removed from the event type. For person
   data (medical notes) silently deleting values on a configuration change is
   unacceptable, so value rows are built lazily and only removed when their
   field is destroyed (§3.2).

### 2.2 The permission patterns we build on

- **Enum + `permission_check` model method.** `CheckinFieldResponse` and
  `Relationship` store an `added_by_*` enum and resolve it in a `case`.
  `PersonFieldValue#permission_check` follows that form.
- **Read/write levels from one list with a containment validation.**
  `Page::PERMISSION_LEVELS = %w[public user team manager admin]`, with
  `viewer` and `editor` drawn from the same list and a validation that the
  editor level can't be broader than the viewer level. `PersonField` uses the
  same shape (§3.3).
- **Explicit-integer enums.** `Badge#permission` maps names to integers
  explicitly; `PersonField` does the same so reordering the list can never
  remap stored values.
- **People helpers on `Person`:** `can_manage(person)`, `all_managed_people`,
  `teams`, `badges`. (`relatives` exists but is deliberately **not** used, §3.4.)
- **Team helpers on `Team`:** `all_descendant_ids`, `all_people`.
- **Per-policy permitted params:** `TeamPolicy#permitted_attributes_for_update`
  is the precedent for varying strong params by role.
- **Feature registration:** `GatherPack::Feature` instances registered in
  `config/initializers/features.rb` with `setup_section` / `setup_items`
  (e.g. Badges → "Badge Types", Events → "Checkin Fields").

### 2.3 What today's code actually allows (verified)

| Question | Today | Source |
|---|---|---|
| Who can view a profile | self, admin, or anyone sharing any team in `all_teams` (which includes ancestors, so under one root team: everyone) | `PersonPolicy#show?` |
| Who can edit a profile | self, admin, or a manager whose `all_managed_teams` overlaps the subject's `all_teams` | `PersonPolicy#update?` |
| Built-in fields shown on the profile | email (from `users`), phone, birthday, address, dietary restrictions, shirt size, gender, shown unconditionally | `people/show.html.erb:24-30` |
| Searchable/sortable | `address`, `birthday`, `dietary_restrictions`, `gender`, `phone_number`, `shirt_size` on `Person`; `person.birthday` on `Membership` | `Person.ransackable_attributes`, `Membership.ransackable_attributes` |
| Choice lists | gender and shirt size from `Settings[:gender_options]`, `Settings[:shirt_sizes]` | `lib/settings.rb:120-121` |
| Parents editing a child's profile | **Not possible**; relatives are not in `update?` | `PersonPolicy#update?` |
| What a relationship means | Directed edge `parent_id` → `child_id` with a `RelationshipType` (`parent_label`, `child_label`, `permission`). No access semantics; `Person#relatives` ignores both type and direction | `app/models/relationship.rb`, `Person#relatives` |
| Who can create a relationship | Per type: `added_by_admin`/`manager`/`team_member`/`participant`/`user`. `added_by_participant` lets **either** side create it | `Relationship#permission_check` |
| How a person gets created | Any signed-in user can `POST /people` (`PersonPolicy` has no `create?`, so `ApplicationPolicy#create?` returns true); no relationship to the creator is made. Self-registration creates a bare `Person` | `PeopleController#create`, `Users::RegistrationsController` |
| Hooks | Architect-written Ruby, `eval`'d synchronously in `after_create/update/destroy` for models that `include CanBeHooked`, matched by `"<table> - <action>"`. `Hook.catalog` lists the selectable events; it has drifted (e.g. `membership_applications` includes `CanBeHooked` but isn't listed; `token - activate` is listed but never fired) | `app/models/concerns/can_be_hooked.rb`, `app/models/hook.rb` |

Two consequences for this design:

- **`all_teams` is the wrong tool for "shares a team".** Because it includes
  ancestors, `viewer.all_teams & subject.all_teams` is true for everyone under a
  shared root. Field audiences use **direct** memberships (`teams`) and
  `can_manage` instead (§3.3).
- **Ransack is an oracle.** `/people?q[dietary_restrictions_cont]=peanut`
  reveals the value even if the view hides it. This feature makes
  `ransackable_attributes` respect read levels (§5).

---

## 3. Data model

Four new tables.

```
person_field_groups ──┐  (sections on the profile)
                      │
badges ──< person_field_badge_grants >── person_fields ──< person_field_values >── people
```

### 3.1 `person_fields` (definition), neat_id prefix `pfd`

| Column | Type | Notes |
|---|---|---|
| `name` | string, required | Label shown in the UI |
| `key` | string, required, unique, `\A[a-z][a-z0-9_]*\z` | Stable identifier for Hooks, Reports, code. Generated from `name` on create; **immutable** after create |
| `data_type` | integer enum | `string: 0, text: 1, boolean: 2, date: 3, integer: 4, select: 5, multi_select: 6, phone: 7, email: 8`. Immutable once any value row exists |
| `options` | jsonb, default `{}` | Per type: `choices` (array) for `select`/`multi_select`; `choices_setting` (Settings key) for system selects; `min`/`max` for `integer`/`date`; `pattern` (regex) for `string` |
| `help_text` | text | Shown under the input on the edit form |
| `read_permission` | integer enum | Who may **see** the value (§3.3). Default `admin` |
| `write_permission` | integer enum | Who may **set** the value (§3.3). Default `admin` |
| `team_id` | uuid, FK, nullable | **Applicability.** When set, the field applies only to people with a direct membership in this team or its descendants. Null = everyone |
| `person_field_group_id` | uuid, FK, nullable | Profile section. Null = the default (top) section |
| `position` | integer, default 0 | Order within the section |
| `required` | boolean, default false | Enforced only when the editor can write the field (§4.4) |
| `show_on_profile` | boolean, default true | Whether readable values appear on `people/show`. When false, the field is still on the edit form (for writers), on the roster page, and in Hooks/Reports. For internal fields like "Background check date" |
| `archived_at` | datetime | Soft delete. Hidden from the profile and forms; values kept; restorable |
| `system_source` | string, nullable, unique | For built-in data (§6), e.g. `"dietary_restrictions"` or `"user.email"`. Never user-editable |

### 3.2 `person_field_values` (value), prefix `pfv`

| Column | Type | Notes |
|---|---|---|
| `person_id` | uuid, FK, required | `Person has_many :person_field_values, dependent: :destroy` |
| `person_field_id` | uuid, FK, required | `PersonField has_many :person_field_values, dependent: :destroy` |
| `value` | text | JSON-encoded typed value (§7). **Plaintext**, like `CheckinFieldResponse#response` |
| `updated_by_id` | uuid → people, nullable | Who last wrote the value; shown on hover in the UI |
| | | Unique index on `(person_id, person_field_id)` |

**Row lifecycle.** Rows are created on first write, not materialized for every
person:

- `Person#field_values_for(fields)` returns existing rows plus in-memory
  `build`s for missing ones (the read half of `refresh_fields`). The form uses
  it, and a row is saved only when the person is saved with a non-blank value.
- Archiving a field, or changing its `team_id` so a person no longer qualifies,
  hides the value but **does not delete it**. Restoring or re-scoping brings it
  back.
- Values are deleted only when the field itself is destroyed (§10.2) or the
  person is destroyed.
- Writing a blank value deletes the row, so "unset" and "never set" look the
  same.

System fields (§6) never have value rows; their accessor reads and writes the
underlying column.

### 3.3 Read and write permission levels

#### Audiences

Each level is a fixed union of **audience components** relative to the subject
(the person the value is about). Admins always pass.

| Component | Who | Check (single subject) |
|---|---|---|
| `subject` | the person themself | `viewer == subject` |
| `guardian` | the **parent side** of an *active guardianship* relationship whose child side is the subject (§3.4). Not "any relative": type and direction both matter | `subject.guardians.include?(viewer)` |
| `leaders` | managers of any team the subject directly belongs to, or of an ancestor of it | `viewer.can_manage(subject)` |
| `teammates` | people who share a **direct** team membership with the subject | `(viewer.team_ids & subject.team_ids).any?` |
| `everyone` | any signed-in user | `true` |

`leaders` reuses `Person#can_manage`, which goes through `all_managed_people`
(people with a membership in a team the viewer manages, or a descendant of one).
That is the "people responsible for this person" rule the app already uses.
`teammates` deliberately uses direct memberships: two people who are only both
under the root team are **not** teammates.

#### Levels

```ruby
PERMISSION_LEVELS = {
  "admin"             => [],
  "self"              => %i[ subject ],
  "leaders"           => %i[ leaders ],
  "self_and_leaders"  => %i[ subject leaders ],
  "guardians"         => %i[ guardian leaders ],
  "family"            => %i[ subject guardian leaders ],
  "team"              => %i[ subject guardian leaders teammates ],
  "everyone"          => %i[ everyone ]
}.freeze
```

Stored with an explicit integer map (`admin: 0, self: 1, leaders: 2,
self_and_leaders: 3, guardians: 4, family: 5, team: 6, everyone: 7`) so
reordering never remaps stored values.

| Level | UI label | Typical use |
|---|---|---|
| `admin` | Admins only | Internal flags, background checks |
| `self` | This person | Private notes the person keeps for themself |
| `leaders` | Their leaders | Leader-only notes |
| `self_and_leaders` | This person and their leaders | **Today's edit rule** for the built-ins |
| `guardians` | Their guardians and leaders (not the person) | Notes a guardian shouldn't share with the child, e.g. behavioral concerns |
| `family` | This person, their guardians, and their leaders | Allergies, medical, emergency contacts |
| `team` | Their teammates, guardians, and leaders | Shirt size, gender |
| `everyone` | Anyone who can see their profile | **Today's read rule** for the built-ins |

`everyone` means "as visible as the person's name": the field shows wherever the
record itself is shown. Any other level is **restricted** (§3.5).

#### Badge grants

Levels are relative to the subject, so they can't express "the health officer
can see every student's allergies". A badge grant adds a **fixed audience** on
top of the level: everyone holding the badge can read (or read and write) the
field.

`person_field_badge_grants` (prefix `pfbg`):

| Column | Type | Notes |
|---|---|---|
| `person_field_id` | uuid, FK, required | |
| `badge_id` | uuid, FK, required | |
| `access` | integer enum | `read: 0, write: 1`. `write` implies read |
| | | Unique index on `(person_field_id, badge_id)` |

Rules:

- **Team-scoped badges scope the grant.** If `badge.team` is set, the grant
  covers only subjects with a direct membership in that team or its
  descendants. A "Den 3 Health Officer" badge reaches Den 3; an org-wide
  "Health Officer" badge reaches everyone the field applies to.
- **Only admin-assigned badges can grant access.** Validation on the grant:
  `badge.added_by_admin?`. Otherwise a self-assignable badge (e.g.
  `added_by_manager_or_self`) would let a member grant themselves access.
- Grants are evaluated in addition to the level. They never remove access.
- Badge grants also cover the "assistant leader who isn't a team manager" case
  without a new role concept.

#### Containment rule (write ⊆ read)

As with `Page`, editing can't be broader than viewing. Validations on
`PersonField`:

- `PERMISSION_LEVELS[write_permission] ⊆ PERMISSION_LEVELS[read_permission]`
  (as sets of components; `everyone` contains every component). Error: "Who can
  edit can't include people who can't see it".
- Every `write` badge grant is also a read grant (enforced by `write` implying
  read in the evaluator; the form shows one control per badge with
  *None / Can see / Can see and edit*).

#### The evaluator

```ruby
class PersonField < ApplicationRecord
  has_neat_id :pfd

  PERMISSION_LEVELS = { ... }.freeze   # as above
  LEVEL_VALUES = { admin: 0, self: 1, leaders: 2, self_and_leaders: 3, guardians: 4, family: 5, team: 6, everyone: 7 }

  enum :read_permission,  LEVEL_VALUES, prefix: :read
  enum :write_permission, LEVEL_VALUES, prefix: :write

  def readable_by?(viewer, subject) = access_for(viewer, subject, :read).present?
  def writable_by?(viewer, subject) = access_for(viewer, subject, :write).present?

  # Returns the reason access is granted (for "Preview as…"), or nil.
  def access_for(viewer, subject, mode)
    return nil if viewer.nil? || !applies_to?(subject)
    return :admin if viewer.admin?
    return :system_read_only if mode == :write && system_read_only?
    level = mode == :read ? read_permission : write_permission
    PERMISSION_LEVELS[level].find { |c| component_includes?(c, viewer, subject) } ||
      badge_grant_for(viewer, subject, mode)
  end

  private

  def component_includes?(component, viewer, subject)
    case component
    when :subject   then viewer == subject
    when :guardian  then subject.guardians.include?(viewer)
    when :leaders   then viewer.can_manage(subject)
    when :teammates then (viewer.team_ids & subject.team_ids).any?
    when :everyone  then true
    end
  end

  def badge_grant_for(viewer, subject, mode)
    grants = person_field_badge_grants.select { |g| mode == :read || g.write? }
    grants.find { |g| viewer.badges.include?(g.badge) && g.covers?(subject) }&.badge
  end
end
```

`access_for` returns a symbol or a `Badge`, which "Preview as…" turns into a
sentence ("leader of Den 3", "holds the Health Officer badge", "guardian via
Parent of"). Everything else uses the boolean readers.

#### Scope form (for lists)

The roster page, the calendar, and events print sheets show a field across many
people. They use `PersonField#readable_subjects_for(viewer)` (and
`#writable_subjects_for`), which returns a `Person` relation built once instead
of calling `readable_by?` per row:

| Component | Relation |
|---|---|
| `subject` | `Person.where(id: viewer.id)` |
| `guardian` | `viewer.wards` (children of the viewer's active guardianship relationships, §3.4) |
| `leaders` | `viewer.all_managed_people` |
| `teammates` | `Person.joins(:memberships).where(memberships: { team_id: viewer.teams.select(:id) })` |
| `everyone` | `Person.all` |
| badge grant | `Person.all`, or the badge team's subtree members if `badge.team` is set |

Combine with `.or` / id-union, intersect with `PersonField.applicable_people`
(below), and `distinct`. A **consistency test** (§11.1) asserts
`readable_subjects_for(v)` equals `Person.select { readable_by?(v, _1) }` across
the fixture world, so the two forms can't drift.

#### Applicability

```ruby
scope :active, -> { where(archived_at: nil) }
scope :applicable_to, ->(person) {
  where(team_id: nil).or(where(team_id: person.all_ancestor_team_ids))
}

def applies_to?(person) = team_id.nil? || person.all_ancestor_team_ids.include?(team_id)
def applicable_people   = team ? Person.joins(:memberships).where(memberships: { team_id: [ team.id ] + team.all_descendant_ids }).distinct : Person.all
```

`all_ancestor_team_ids` (the subject's direct teams plus their ancestors) is the
correct test for "is in this team's subtree". `Team#all_people` is **not** used
here because it adds ancestor managers, so a pack leader would get the
"Students" fields.

### 3.4 Guardianship on relationship types

Field access never flows through "any relationship". It flows only through
relationship types an admin has explicitly marked as conferring guardianship,
and only from the parent side to the child side.

#### Column

`relationship_types.guardianship`, integer enum, default `none`, not null:

| Value | Meaning | Example types |
|---|---|---|
| `none: 0` | No field access. Every existing and new type starts here | Sibling of, Mentor of |
| `minor: 1` | The parent side is a guardian of the child side, **subject to the age settings below** | Parent of, Legal guardian of |
| `consented: 2` | The parent side is a guardian of the child side **regardless of age**. Created by the child side, so an adult grants it to someone | Authorized family contact |

#### Who can create guardianship relationships

A guardianship relationship grants read (and possibly write) access to someone
else's data, so creation is tighter than for ordinary types:

- **`minor` types must have `permission: added_by_admin` or
  `added_by_manager`.** Validation on `RelationshipType`: "Guardianship types
  can only be added by admins or managers". This closes the hole where a member
  self-declares "Parent of" an existing child. (The one planned exception, a
  guardian creating a brand-new child record, belongs to the family
  registration feature, §14.)
- **`consented` relationships can only be created by the child side or an
  admin.** `Relationship#permission_check` gets one extra condition for
  `consented` types: `created_by == child || created_by_admin?`, whatever the
  type's `permission`. The parent side can never self-declare consent.
- Either side, or a manager or admin, can **delete** a `consented`
  relationship, so an adult can revoke access they granted. A `minor`
  relationship can be deleted (or reversed) only by a manager of either side
  or an admin, so a child can't cut off their guardian.

#### Age settings (off by default)

Two new `Settings` under "People" (`lib/settings.rb`, `add_setting`). Both
default to doing nothing:

| Setting | Type | Default | Effect |
|---|---|---|---|
| `guardianship_age_limit` | integer | blank (off) | When set (e.g. `18`), a `minor` relationship stops conferring guardianship once the child side's `birthday` shows they've reached this age. When blank, `minor` guardianship never expires on its own |
| `guardianship_ends_without_birthday` | boolean | `false` | Only used when the age limit is set. `false`: guardianship continues for children with no birthday on file. `true`: it stops. (A boolean rather than a `keep`/`end` string because the Settings page renders booleans as a select and has no other choice input) |

With both at their defaults, `minor` and `consented` behave identically. An
organization that serves minors turns on the age limit when it wants the
automatic cutoff. Expiry is computed at check time from `birthday`; nothing is
deleted, and lowering or clearing the setting restores access.

#### Model

```ruby
class Person
  # People who are guardians of this person right now.
  def guardians
    Person.where(id: Relationship.active_guardianships.where(child_id: id).select(:parent_id))
  end

  # People this person is currently a guardian of.
  def wards
    Person.where(id: Relationship.active_guardianships.where(parent_id: id).select(:child_id))
  end

  def guardianship_expired? # true only when the age limit is set and reached (or no birthday + "end")
end

class Relationship
  # Guardianship types whose child side hasn't aged out, in SQL:
  # consented, or minor AND (limit blank OR birthday > today - limit years
  #   OR (birthday IS NULL AND NOT ends_without_birthday))
  scope :active_guardianships, -> { ... }
end
```

`Person#relatives` is unchanged and still used by the relationships pages; the
field system just doesn't use it.

#### Staying out of the way

An organization that never marks a type as guardianship sees no change. The
`guardian` component is always empty, so `family` collapses to "this person and
their leaders" and `guardians` to "their leaders". While **no** relationship
type has `guardianship` other than `none`, the field form **hides** the
`guardians` level and labels `family` and `team` without the word "guardians"
(§10.3). No birthday lookups run unless the age limit is set.

**HBR setup:** mark "Parent of" (or the equivalent) as `minor`, confirm its
`permission` is admin/manager, set `guardianship_age_limit` if wanted, then
apply recommended privacy settings.

### 3.5 Restricted fields

A field whose `read_permission` is anything other than `everyone` is
**restricted**. Restricted fields are automatically:

- excluded from `Person.ransackable_attributes` and
  `Membership.ransackable_attributes` for non-admins (never searchable or
  sortable),
- excluded from the API (`Api::V1::UserInfoController`), and
- covered by `filter_parameters` (all `person_field_values` params are filtered
  regardless).

There's no separate sensitivity classification; the read level is the single
axis.

### 3.6 `person_field_groups` (sections), prefix `pfgr`

`name` (required), `position`. `has_many :person_fields, dependent: :nullify`.
Purely presentational: sections on the profile and the edit form, ordered by
`position`. Ungrouped fields render first, under no heading.

---

## 4. Access evaluation and enforcement

### 4.1 Model readers

Convenience readers on `Person`, matching the fat-model style already there:

```ruby
class Person
  has_many :person_field_values, dependent: :destroy

  def readable_fields_for(viewer)
    PersonField.active.applicable_to(self).ordered.select { |f| f.readable_by?(viewer, self) }
  end

  def writable_fields_for(viewer)
    PersonField.active.applicable_to(self).ordered.select { |f| f.writable_by?(viewer, self) }
  end

  # Trusted accessors for Hooks, Reports, jobs, and the console. No viewer check.
  def field_value(key)               # cast value, or nil
  def set_field_value(key, value)    # writes the column (system) or the value row
end
```

`PersonField.ordered` sorts by group position, then field position, then name.
Load `person_field_badge_grants: :badge` with the fields to avoid N+1 queries on
the profile.

### 4.2 Pundit integration

No per-field policy for values. Extend `PersonPolicy`:

```ruby
def readable_person_fields = record.readable_fields_for(person)
def writable_person_fields = record.writable_fields_for(person)

# Today's rule, unchanged: who may edit the base profile.
def update_profile?
  record == person || user.admin? || (person.all_managed_teams & record.all_teams).any?
end

# A parent who can write a family-level field can now reach the edit form.
def update?
  update_profile? || writable_person_fields.any?
end
alias_method :edit?, :update?

def permitted_attributes
  attrs = []
  attrs += [ :first_name, :last_name, :display_name, :avatar, :bio ] if update_profile?
  attrs += [ :user_id, team_ids: [], badge_ids: [] ] if user.admin?
  attrs << { person_field_values: writable_person_fields.map(&:key) }
  attrs
end
```

The `_form` hides base inputs when `update_profile?` is false, so a parent
editing their child's allergies sees only the fields they can write (plus
readable-but-not-writable values as read-only text).

Admin-only policies for the definitions: `PersonFieldPolicy`,
`PersonFieldGroupPolicy`, and `PersonFieldBadgeGrantPolicy` inherit from
**`AdminPolicy`**, like `CheckinFieldPolicy`. The custom scaffold generator
produces a permissive policy (AGENTS.md), so this is a hand edit after
generating. Exception: `PersonFieldPolicy#roster?` (§10.6) is
`user.admin? || record.readable_subjects_for(person).exists?`.

### 4.3 Where enforcement lives

Reads are enforced in the **views, serializers, and list scopes** (they ask
`readable_person_fields` or `readable_subjects_for`). The model does **not**
hide values from trusted callers. Hooks, Reports, jobs, and the console run
without a viewer, exactly as they already read `person.dietary_restrictions`.
That matches how `Report#code` and `Page#dynamic` are trusted (admin/architect
only).

Writes are enforced twice:

1. Strong params permit only `writable_person_fields` keys.
2. `PersonFieldValue#permission_check` (the `CheckinFieldResponse` pattern,
   using `writable_by?(Current acting person, person)`) rejects a disallowed
   write with a validation error. System-field writes go through the same check
   in `Person#assign_field_values`. The acting person comes from the same place
   `User` already uses for `acting_user` checks.

### 4.4 Saving

`PeopleController#update` passes `person_field_values` to
`Person#assign_field_values(hash, acting:)`, which:

1. Ignores keys that aren't writable (they were already dropped by strong
   params; this is defense in depth).
2. Casts each value with `PersonField#cast` and validates it against `options`
   (choice in list, min/max, pattern, email/phone format).
3. Enforces `required` only for fields the actor can write. A required field the
   actor can't write never blocks a save.
4. Writes system fields to their column and custom fields to value rows, setting
   `updated_by_id`.
5. Adds errors to `person.errors` keyed by field `key`, so `simple_form` shows
   them inline.

Everything runs inside the person's save transaction.

### 4.5 Explaining access ("This field is not visible to your child")

Levels, guardianship types, age settings, and badge grants are all fixed
configuration, so for any field and subject the system can state exactly who
can see and change it. That state is exposed to users as plain-language
messages.

#### The audience object

```ruby
# Returns each audience role's access to this field for this subject:
# { subject: :write, guardians: :read, leaders: :write, teammates: :none,
#   everyone: :none, badges: { <Badge> => :read }, guardianship_ends_on: Date|nil }
PersonField#audience_for(subject)
```

- Each role gets `:none`, `:read`, or `:write`, derived from the level
  components and badge grants with the write ⊆ read rule.
- `guardians` is reported only when the subject currently has a guardian, so
  people without guardians (including guardians themselves) never see notes
  about them.
- `guardianship_ends_on` is set when the age limit applies to this subject
  (birthday + limit), so a guardian can be warned before access ends.
- System-field specifics are included, e.g. email: "changed in account
  settings".

#### Messages

`PersonFieldsHelper#access_notes(field, subject, viewer)` turns the audience
into one or two short sentences **relative to the viewer's role**. Names use
`display_name`:

| Viewer is | Situation | Message |
|---|---|---|
| Guardian | subject `:none` | "Not visible to Alex." |
| Guardian | subject `:read` | "Alex can see this but can't change it." |
| Guardian | subject `:write` | "Alex can see and change this." |
| Guardian | guardianship ends soon | "Your access to Alex's restricted fields ends on Mar 3, 2027." |
| Subject | guardians `:read`/`:write` | "Your guardians can see this." / "Your guardians can see and change this." |
| Subject | only leaders can write | "Only your leaders can change this." |
| Leader | guardians `:none` | "Alex's guardians can't see this." |
| Leader | subject `:none` | "Alex can't see this." |
| Anyone | badge grant present | "Also visible to Health Officer badge holders." |
| Anyone | summary (tooltip) | "Visible to: Alex, Alex's guardians, Alex's leaders, Health Officer." |

Only the notes that add information appear: a field visible to everyone shows
none. These templates live in the locale file so wording can change without
code changes.

#### Rules

- **Never reveal a field the viewer can't read.** A message is only rendered on
  a field the viewer can already see. No "there are N fields you can't see"
  notice, no empty headings, no counts, because the existence of a field like
  "Behavioral concerns" on a child's record is itself sensitive.
- Admins see the summary form on every field, plus the "Why" from Preview as…
  (§10.4).

#### Where messages appear

- **Edit form:** a muted line under each input (after help text).
- **Profile:** the lock-icon tooltip on restricted fields.
- **Field form (setup):** a live preview of the summary sentence as levels and
  badges change.

---

## 5. Every read path must be covered

This is the practical definition of "doesn't leak". Each row needs a test
(§11.2).

| Surface | Change |
|---|---|
| `people/show.html.erb` | Replace the hard-coded email/phone/birthday/address/dietary/shirt/gender block with `render "people/fields", person: @person`, iterating `policy(@person).readable_person_fields.select(&:show_on_profile)` grouped by section. Empty values render as "—"; a section with no readable fields is omitted |
| `people/_form.html.erb` | Render inputs for `writable_person_fields` by section; readable-only values as read-only text; base inputs only when `update_profile?` |
| `PeopleController#person_params` | `permitted_attributes(@person)` (§4.2) |
| **Ransack** (`Person`, `Membership`) | `ransackable_attributes(auth_object)` returns base columns plus system columns whose field is **not** restricted, or everything for admins. Pass `auth_object: current_user` at every `ransack` call (`people#index`, `search#*`, `calendar#calendar`, memberships). The "Age" sort link renders only when `birthday` is ransackable for the viewer. `person_field_values` is never ransackable. Ransack also reaches `Person` **through associations** (`person` on `Checkin`, `Question`, `Reply`, `TimeClockPunch`, `MembershipApplication`, e.g. `q[person_dietary_restrictions_cont]` on an event's checkins), and those call sites don't pass `auth_object`. So `Person.ransackable_attributes` **fails closed**: a nil `auth_object` gets the non-admin attribute set |
| `CalendarController` birthdays | Restrict `@birthdays` to `birthday_field.readable_subjects_for(current_person)` |
| `SearchController#combo` | Already exposes only `identifier_name`; add a regression test so it stays that way |
| `Api::V1::UserInfoController` | No field values in v1, only base claims (email stays governed by the `user_email` OAuth scope, since it's the user's own data) |
| Roster page (§10.6) | Rows restricted to `readable_subjects_for` |
| Events `print` / `arrange`, `checkins/show` | See §9 |
| Hooks | See §8.1. Hooks receive unfiltered values; hook code is architect-trusted |
| PaperTrail / AuditLog views | Audit-log views are admin-only today; confirm with a test that a non-admin can't open the versions of a `PersonFieldValue` |
| Logs | Add `:person_field_values`, `:dietary_restrictions`, `:address`, `:phone_number`, `:birthday` to `filter_parameters` |
| Turbo/fragment caching | None today. If added, cache keys must include the viewer's access fingerprint |
| Flash / error pages | Never interpolate field values into flash messages or error text |

---

## 6. Bringing the built-in data under the same control

Seed one `person_fields` row per built-in, with `system_source` set:

| Field | `system_source` | `data_type` | `options` | Section |
|---|---|---|---|---|
| Email | `user.email` | `email` | | Contact |
| Phone | `phone_number` | `phone` | | Contact |
| Address | `address` | `string` | | Contact |
| Birthday | `birthday` | `date` | | Details |
| Dietary Restrictions | `dietary_restrictions` | `string` | | Details |
| Shirt Size | `shirt_size` | `select` | `{ "choices_setting": "shirt_sizes" }` | Details |
| Gender | `gender` | `select` | `{ "choices_setting": "gender_options" }` | Details |

The seed also creates two sections, "Contact" and "Details", in that order,
which reproduces today's profile layout. Admins can rename, reorder, or move
fields between them.

Rules for system fields:

- The accessor reads/writes the column. No data migration, and no change to
  Hooks/Reports that call `person.dietary_restrictions`.
- `system_source` fields can't be destroyed (archiving is allowed and hides
  them). `key`, `data_type`, `options`, and `team_id` are fixed.
- **Email is read-only in this system.** It is shown and its visibility is
  controlled here, but it is changed through the account (Devise), so its write
  level is fixed at `admin` and the form disables that control ("Managed by
  account settings"). People without a user show "No account attached."
- **Choice lists stay in Settings.** For `choices_setting` fields the editor
  shows the current choices read-only with a link to Settings → People.

### 6.1 Upgrade defaults: no behavior change until an admin decides

The seeding migration sets every system field to **today's behavior**:
`read_permission: everyone`, `write_permission: self_and_leaders` (email:
`write: admin`). Upgrading changes nothing visible. This matters for
upstreaming: a release that silently hides data from people who saw it
yesterday would be a surprise.

The field index offers **"Apply recommended privacy settings"** (one admin
action, audited, with a confirmation listing the changes):

| Field | Read | Write |
|---|---|---|
| Dietary Restrictions | `family` | `family` |
| Phone, Address, Birthday | `family` | `family` |
| Email | `team` | (account) |
| Gender, Shirt Size | `team` | `family` |

Guardians can edit every detail except email, since they often keep a
child's details current. (An earlier revision left phone, address, birthday,
gender, and shirt size at `self_and_leaders`; in practice guardians needed to
edit them.)

For HBR this is a single click after deploying Phase 2.

### 6.2 Seeding mechanics

`PersonField.ensure_system_fields!` is idempotent (`find_or_create_by!
system_source:`; never overwrites levels an admin changed). It's called from the
Phase 2 data migration and from `db/seeds.rb`. The migration defines a minimal
inline model class rather than calling app models, so it keeps working as the
models evolve.

---

## 7. Storage and types

- `value` is text holding a JSON-encoded typed value (`"true"`,
  `"\"2026-01-02\""`, `["peanut","shellfish"]`). `PersonField#cast(raw)` and
  `#serialize(input)` convert per `data_type`:

| `data_type` | Input (simple_form) | Stored | Validation |
|---|---|---|---|
| `string` | `:string` | string | optional `pattern` |
| `text` | `:text` | string | |
| `boolean` | `:boolean` (checkbox) | `true`/`false` | |
| `date` | `:string`, `type: date` | ISO date | optional `min`/`max` |
| `integer` | `:integer` | integer | optional `min`/`max` |
| `select` | `:select` from `choices` | string | must be in `choices` |
| `multi_select` | `:check_boxes` from `choices` | array of strings | each in `choices` |
| `phone` | `:tel` | string | loose phone format |
| `email` | `:email` | string | `URI::MailTo::EMAIL_REGEXP` |

- **Removing a choice** from a select doesn't rewrite stored values. The profile
  shows the old value, and the edit form keeps it selectable for that person
  (marked "(retired)") until it's changed.
- **Plaintext**, like `CheckinFieldResponse#response`. That's consistent with
  how the app stores every other string, and it keeps Hooks, Reports, and the
  console working unchanged.

**Deferred: confidential-at-rest.** Encrypting a field so that even a DB dump or
the audit log can't reveal it is a separate decision, because the app's current
trust model would undercut it: an architect can read any value through a
`Report` (`eval`), Hooks fire on changes, and PaperTrail records edits.
Per-field encryption without also constraining Reports, Hooks, and backups would
promise a guarantee the system doesn't actually honor. It can be added to
`PersonFieldValue` later without reshaping this design.

---

## 8. Auditing and Hooks

- `PersonField`, `PersonFieldGroup`, and `PersonFieldBadgeGrant` get
  `has_paper_trail versions: { class_name: "AuditLog" }` like every other model.
  Changing a field's read level or a badge grant is security-relevant and is
  audited.
- `PersonFieldValue` gets `has_paper_trail` too, as `CheckinFieldResponse` does.
  System-field changes are already audited through `Person`'s paper trail.
- "Apply recommended privacy settings" writes one version per changed field.
- **Deferred:** logging *reads* ("who viewed this allergy") belongs with the
  confidential-at-rest decision, not v1.
- `RelationshipType` already has a paper trail; changes to `guardianship` are
  audited with no extra work.

### 8.1 Hooks

Hooks are GatherPack's integration surface: architect-written Ruby run for
`"<table> - <action>"` events (§2.3), which can call third-party APIs. New
functionality gets hooks where it matches the existing pattern: meaningful
records get create/update/destroy, plus a named domain event where the record
events alone would make an integration awkward.

#### Record events (`include CanBeHooked`, add to `Hook.catalog`)

| Table | Why |
|---|---|
| `person_field_values` | Core data. Mirrors `checkin_field_responses`, which is already hooked |
| `person_fields` | Definition changes, including read/write level changes, which an integration may need to mirror (e.g. sync a field to an external roster only while it's `everyone`) |
| `person_field_badge_grants` | Grants change who can see restricted data, the same vein as `badge_assignments` |
| `relationship_types` | Not hooked today, but marking a type as guardianship now changes data access. Same vein as `badges` |

**Not hooked:** `person_field_groups`. They're presentational only, and a
section rename has no integration value.

#### Domain event: `person_fields - value changed`

One event per changed field per save, for **both** system and custom fields.
Without it, "notify the health officer when allergies change" would have to
handle four shapes: `people - update` with a column diff for system fields, and
`person_field_values - create/update/destroy` for custom ones (a blank write
deletes the row).

- `model` is a `PersonFieldChange` (plain Ruby object, `app/models/person_field_change.rb`):
  `person`, `field`, `old_value`, `new_value` (both cast), `changed_by`.
  Hook code reads `model.field.key == "food_allergies"`.
- Fired from `Person#assign_field_values` after a successful save, the same
  timing as the existing `after_update` hooks:
  `Hook.where(event: "person_fields - value changed").each { |h| h.run(change) }`.
- Added to `Hook.catalog` alongside `token - activate`.

#### Considered and deferred

- **`guardianship - expired`.** Age-based expiry is computed at check time, so
  nothing happens at the moment someone turns 18. A hook would need a daily
  job to detect crossings. Add it if an integration needs it; the
  `guardianship_ends_on` date in `audience_for` makes the job trivial.
- **Catalog drift** (models that include `CanBeHooked` but aren't in
  `Hook.catalog`, e.g. `membership_applications`, `checkin_field_responses`).
  This is a pre-existing upstream bug and gets its own small branch, not this
  feature.

#### Data handling note

Hooks receive **unfiltered** values, including restricted fields, exactly as
Reports do; hook code is architect-trusted. The Hook form shows a notice when
the selected event is in the person-fields family: "This hook receives
restricted personal data. Only send it to systems approved to hold it."

---

## 9. Integration with Events (Phase 3)

Organizers want allergies on a campout check-in sheet. Rather than copy the
value into a `CheckinFieldResponse` (no read control, and a stale copy), add a
nullable `checkin_fields.person_field_id`:

- A check-in field linked to a person field is **read-only and computed**; it
  shows the person's current value and is skipped by `refresh_fields` /
  `permission_check`.
- `events#print`, `events#arrange`, and `checkins/show` show the value only for
  subjects in `person_field.readable_subjects_for(current_person)`, and "—"
  otherwise.
- The `CheckinField` form gets a "Show person field" select (active,
  non-archived person fields) as an alternative to a free-response field.

The same phase gives plain `CheckinField` a `read_permission` too, so responses
like "medication given at 3pm" don't have the same exposure problem. It's
defined relative to the participant using the same components and levels
(`PersonField::PERMISSION_LEVELS`), with a default of `everyone` to preserve
today's behavior.

---

## 10. UX

### 10.1 Registration and navigation

```ruby
GatherPack::Features.register_built_in(
  GatherPack::Feature.new(
    key: :person_fields,
    label: "Custom Person Fields",
    description: "Add your own fields to member profiles and control who can see them",
    default_enabled: false,
    nav_section: "People",
    nav_position: 30,
    nav_items: [ GatherPack::Feature::NavItem.new(label: "Member Info", path: :roster_person_fields_path, icon: "clipboard-list") ],
    setup_section: "People",
    setup_items: [
      GatherPack::Feature::SetupItem.new(label: "Person Fields", path: :person_fields_path),
      GatherPack::Feature::SetupItem.new(label: "Person Field Sections", path: :person_field_groups_path)
    ]
  )
)
```

**What the flag gates.** The toggle controls *custom* fields: creating them,
showing them, and the Member Info nav. Access control on the **system fields is
always enforced**, so turning the feature off never re-exposes a field an admin
restricted. The Person Fields setup page is therefore always routed. With the
feature off it lists only system fields and hides "New field". Because system
fields default to today's behavior (§6.1), the flag-off upgrade changes nothing.

The `nav_items` entry shows only when the viewer has at least one field with
readable subjects; the nav renderer checks a `visible_if` lambda (or the view
guards with `policy`), whichever pattern the nav already supports. Confirm
during implementation.

### 10.2 Setup → Person Fields: index (the access matrix)

One table, grouped by section, ordered by position. Columns: **Name** (key in
muted text), **Type**, **Applies to** (team or "Everyone"), **Who can see**,
**Who can edit**, **Badge access** (chips: "Health Officer: see"),
**On profile** (✓/—), **Status** (active/archived, "System" tag).

- Row actions: Edit, Move up / Move down (swaps `position` within the section),
  Archive/Restore, Preview.
- Filter: "Show archived".
- Banner when any field uses a level with the `guardian` component but no
  relationship type has `guardianship` set: "No relationship types grant
  guardianship yet, so guardians won't have access", linking to Relationship
  Types.
- Buttons: "New field" (custom fields only), "Apply recommended privacy
  settings" (§6.1), "Preview as…" (§10.4).

This page is the "can I see the whole security posture at a glance" view.

### 10.3 Field form (new/edit)

Fields, top to bottom:

1. **Name**. **Key** is shown as it will be generated, editable on create,
   read-only after ("Used by Hooks and Reports; can't be changed").
2. **Type**. Locked once values exist ("Archive this field and create a new one
   to change its type").
3. **Type-specific options**, shown and hidden by type with a small Stimulus
   controller:
   - select / multi-select: **Choices**, a textarea with one choice per line
     (stored as the `choices` array; blank lines dropped; duplicates rejected).
   - integer / date: **Minimum**, **Maximum**.
   - string: **Validation pattern** (regex; validated on save so a bad regex
     can't be stored) plus **Pattern hint** shown on mismatch.
   - System selects: read-only choices with a link to Settings.
4. **Help text**.
5. **Section** (select of groups, blank = top). **Applies to** (team select,
   blank = everyone). **Required**. **Show on profile**.
6. **Who can see this** and **Who can edit this**: selects using the UI labels
   from §3.3, each with a one-line description under it that updates on change
   ("This person, their guardians (Parent of, Legal guardian of), and the
   managers of their teams"). The description names the guardianship types
   currently configured. The containment error (§3.3) shows inline. **While no
   relationship type has guardianship set, the `guardians` option is hidden
   and `family`/`team` are labeled without guardians** ("This person and their
   leaders"), so an all-adult organization never sees family terminology
   (§3.4).
7. **Badge access**: a row per granted badge with *Can see / Can see and edit*
   and a remove button, plus an "Add badge" select limited to badges with
   `permission: added_by_admin`. If the badge has a team, the row notes "Only
   for members of <team>". Implemented as nested attributes
   (`accepts_nested_attributes_for :person_field_badge_grants, allow_destroy:
   true`), matching how simple_form nested forms are used elsewhere, or as
   inline turbo-frame add/remove if there's no nested-form precedent. Check
   before building.
8. **Warnings** panel (non-blocking): no guardianship types exist when a
   guardian level is chosen; "Required, but only admins can edit" when
   `required` is set with write level `admin`.

**Archive** sets `archived_at` and is reversible. **Delete** is offered only
for archived, non-system fields, and the confirmation states how many values
will be destroyed. This uses the standard `data-turbo-confirm`, so no custom
modal.

### 10.4 Preview as…

Setup page with two person pickers (reuse the `search#combo` person picker):
**Viewer** and **Subject**. It renders every active applicable field with:

| Field | Can see | Can edit | Why |
|---|---|---|---|
| Food Allergies | ✓ | ✓ | Leader of Den 3 |
| Medical Notes | ✓ | — | Holds the Health Officer badge |
| Background Check | — | — | Admins only |

"Why" comes from `access_for` (§3.3). There's also a link to view the subject's
profile **as rendered for that viewer**: the same `people/fields` partial with
the viewer swapped. This is admin-only and doesn't impersonate the session. It
is the best guard against a misconfiguration and should be used before applying
recommended settings.

### 10.5 Profile and edit form

- **Profile (`people/show`)**: the `people/fields` partial replaces lines 24-30
  in the same column. Each section renders as a small heading plus the existing
  `<p><b>Label: </b>value</p>` style, so the page looks unchanged when nothing
  is restricted. Values are formatted per type (dates with `nice_date`,
  booleans as Yes/No, multi-select joined by ", ", email as a `mail_to`,
  phone as a `tel:` link). A restricted field the viewer can see gets a small
  lock icon with a tooltip ("Visible to: this person, their family, and their
  leaders"), so people understand why a teammate can't see it.
- **Edit form**: the system fields' current inputs are replaced by the same
  field-driven rendering, in sections. Help text goes under inputs, required
  fields are marked as simple_form does, and readable-only values show as
  disabled text with "Only <level label> can change this". Hover on a custom
  value shows "Last updated by X" (from `updated_by_id`).
- **Parent access**: a parent who can only write family-level fields gets an
  "Edit" button on their child's profile (via `PersonPolicy#edit?`), and the
  form contains only those fields.

### 10.6 Member Info (roster)

`GET /person_fields/roster`: pick one or more fields the viewer can read for
someone, and optionally a team. It renders a table of people × selected fields,
restricted per field to `readable_subjects_for(viewer)` and intersected with
`policy_scope(Person)`. Cells for subjects the viewer can't read for a given
field show "—", and rows with no readable cells are omitted.

- Includes a print stylesheet (campout allergy sheet).
- This is how a health officer, or a den leader, gets "all my kids' allergies"
  without opening each profile.
- `PersonFieldPolicy#roster?` gates access (§4.2).

### 10.7 Setup → Person Field Sections

Plain scaffold: name, position, with move up/down on the index. Deleting a
section ungroups its fields (`dependent: :nullify`).

### 10.8 Relationship Types, Settings, and the relationships page

- **Relationship Types form**: a **Guardianship** select (*None* / *Guardian
  while the child is a minor* / *Guardian with the child's consent*) with help
  text: "Guardians can see and edit fields set to family or guardian levels on
  the child-side person's profile." The `permission` validation error (§3.4)
  shows inline. The Relationship Types index shows a "Guardian" tag on these
  types.
- **Settings → People**: the two age settings (§3.4) with descriptions. The
  second setting's description says "Only applies when an age limit is set";
  it isn't disabled, because the Settings page has no per-setting state.
- **Relationships page** (`people/relationships`): an adult on the child side
  of a `minor` relationship whose guardianship has expired sees "No longer has
  access to your restricted fields" next to it, and an "Allow access" action
  that creates a `consented` relationship of a type the admin designates
  (the first `consented` type, or a setting if there are several). This is
  the adult student's path to re-grant a parent access, or to add an
  emergency contact who can see their info.

### 10.9 Routes

```ruby
resources :person_fields do
  collection { get :roster; get :preview; post :apply_recommended }
  member     { patch :move; patch :archive; patch :restore }
end
resources :person_field_groups do
  member { patch :move }
end
```

Routed unconditionally (§10.1). The controllers check
`GatherPack::Features.enabled?(:person_fields)` for custom-field-only actions
(`new`, `create`, `roster`).

---

## 11. Testing strategy

The suite is mostly unrun scaffold output (AGENTS.md); this feature must not
follow that. Minimum:

1. **Evaluator unit tests** (`test/models/person_field_test.rb`). Fixture world:
   Org → Pack → Den A / Den B, plus a separate root team "Other Org". Members:
   student A1 and A2 in Den A, student B1 in Den B, A1's parent (a "Parent
   of" relationship, type `guardianship: minor`), A2's parent, A1's sibling
   (a "Sibling of" relationship, type `guardianship: none`, who must get no
   access), Den A leader, Den B leader, Pack
   leader, a Den A assistant (non-manager) holding a Den A–scoped "Assistant"
   badge, an org-wide "Health Officer" badge holder, an admin, and an
   unrelated member of Other Org.
   - Assert the **full read and write matrix** for every level × every viewer
     against subject A1.
   - **`team` regression**: B1 and the Other Org member are *not* teammates of
     A1. This is the ancestor bug the old design had.
   - **`leaders` regression**: a manager of a sub-team of a team the subject
     manages is *not* responsible for the subject.
   - **Badge grants**: the team-scoped badge reaches Den A only; the org-wide
     badge reaches everyone; a write grant implies read; a non-admin-assigned
     badge can't be granted (validation).
   - **Containment validation**: write `family` with read `leaders` is invalid;
     write `self_and_leaders` with read `family` is valid.
   - **Applicability**: a Students-only field doesn't apply to the Pack leader.
   - **Consistency**: `readable_subjects_for(v)` equals the per-subject result
     for every viewer (and the same for writable).
2. **Leak tests** (integration). For each surface in §5, sign in as A2's parent
   and as the Den B leader and assert A1's allergy value never appears:
   `people/show`, `people/edit`,
   `GET /people?q[dietary_restrictions_cont]=…`, the "Age" sort,
   `memberships` ransack on `person.birthday`, the calendar JSON, `search/combo`,
   the API `userinfo` endpoint, the roster page, and the audit log.
3. **Write tests**:
   - A crafted `PATCH /people/:id` with a `person_field_values` key the viewer
     can't write is dropped by strong params, and calling `assign_field_values`
     directly is rejected by `permission_check`.
   - A1's parent can edit A1's allergy but not A1's name or bio.
   - A required field the actor can't write doesn't block the actor's save.
   - Email can't be written through field params.
4. **Guardianship tests** (`test/models/relationship_test.rb`,
   `person_test.rb`):
   - A relationship of a `none` type grants nothing, in either direction.
   - A `minor` relationship grants parent → child only; the child gets no
     access to the parent's `family` fields.
   - A `minor` type with `permission: added_by_participant` fails validation.
   - A `consented` relationship created by the parent side is rejected; created
     by the child side or an admin, it succeeds; the child side can delete it.
   - Age settings: with the limit blank, an adult child's guardian keeps access;
     with the limit at 18, access ends on the 18th birthday, and missing
     birthdays follow `guardianship_ends_without_birthday`. `consented` ignores the
     limit. `Person#guardians` and `Person#wards` agree with
     `Relationship.active_guardianships`.
   - With no guardianship types, the field form doesn't offer `guardians`.
5. **Messaging tests** (`test/helpers/person_fields_helper_test.rb`):
   `audience_for` for each level and badge combination; `access_notes` for
   each row of the §4.5 table; no note is rendered for a field the viewer can't
   read, and the profile HTML for a viewer contains no trace of an unreadable
   field (name, key, or section heading).
6. **Hook tests**: a `person_fields - value changed` hook fires once per
   changed field for a system field and a custom field, with the right
   `old_value`/`new_value`/`changed_by`; it doesn't fire for unchanged fields
   or failed saves. `person_field_values - create`, `relationship_types -
   update`, and `person_field_badge_grants - create` fire. Every new event is in
   `Hook.catalog`.
7. **Lifecycle tests**: archiving keeps values; re-scoping `team_id` keeps
   values; destroying a field destroys values; removing a choice keeps the
   stored value.
8. **Upgrade tests**: after `ensure_system_fields!`, a non-admin teammate sees
   exactly what they saw before (profile and ransack), and running it twice
   doesn't change admin-edited levels. Existing relationship types are
   `guardianship: none` after migration.
9. **System tests** (one each): create a select field with badge access in
   Setup, then see it on the profile as an allowed viewer and not as a
   disallowed one; use Preview as…; as a guardian, edit a child's
   `guardians`-level field and see "Not visible to <child>".

Add these to CI's `test` job; consider returning `test` to `publish`'s `needs`
once this slice is green (AGENTS.md).

---

## 12. Rollout plan

| Phase | Scope | Breaks anything? |
|---|---|---|
| **0: Read-surface prep** | `auth_object: current_user` at the `Person`/`Membership` ransack call sites (`ransackable_attributes(auth_object)` still returns today's attributes); `filter_parameters` additions. `verify_authorized`/`verify_policy_scoped` on `InternalController` was dropped from this phase: about 15 controllers have actions that never call `authorize` (some are real gaps, e.g. announcements `update`/`destroy`), so it belongs in its own hardening change | No |
| **1: Model + UI** | `PersonField`, `PersonFieldValue`, `PersonFieldGroup`, `PersonFieldBadgeGrant` (scaffold, then hand-edit policies); the evaluator and scope form; `Person#readable_fields_for`/`writable_fields_for`/`field_value`/`assign_field_values`; **guardianship** (`relationship_types.guardianship`, `Relationship.active_guardianships`, `Person#guardians`/`#wards`, consent rule in `Relationship#permission_check`, age settings); `audience_for` and access messages; Setup index, form, sections, archive/restore; Preview as…; profile and form partials for custom fields; `PersonPolicy#update?` widening; Member Info roster; hooks (§8.1); feature registration | No. Feature flag off by default |
| **2: System fields** | `ensure_system_fields!` migration (today's levels); switch `people/show`, `_form`, Ransack, calendar, and strong params to the field API; email as a read-only system field; "Apply recommended privacy settings" | No, by default (§6.1). Applying the recommended settings hides data from people who used to see it. That's the intended result, and the release notes should say so |
| **3: Events integration** | §9: linked check-in fields, plus a read level on `CheckinField` | No (defaults preserve today) |
| **4: Later, if wanted** | Badge-refined narrowing (§13.1), moving columns into the value table, confidential-at-rest (§7), read-access logging, CSV export from the roster | No |

Migrations in phases 1–3 touch the **primary** DB only. Per AGENTS.md, run both
`db:migrate:primary` and `db:migrate:versions` even so (the audit DB is
separate). All migrations are reversible; the Phase 2 data migration's `down`
deletes only rows with `system_source` set.

### 12.1 Files

New: `app/models/person_field{,_value,_group,_badge_grant,_change}.rb`, the
matching controllers, policies, views, and tests,
`app/helpers/person_fields_helper.rb`, `app/views/people/_fields.html.erb`,
`app/views/people/_field_inputs.html.erb`, a Stimulus controller for the
type-specific options, and migrations.

Existing upstream files touched (record in `FORK.md` while this is carried):
`app/models/person.rb`, `app/models/membership.rb`,
`app/models/relationship.rb`, `app/models/relationship_type.rb`,
`app/views/relationship_types/_form.html.erb` (and index),
`app/views/people/relationships.html.erb`, `lib/settings.rb`,
`app/views/hooks/_form.html.erb` (data-handling notice),
`config/locales/en.yml` (access messages),
`app/policies/person_policy.rb`, `app/controllers/people_controller.rb`,
`app/controllers/calendar_controller.rb`, `app/controllers/search_controller.rb`
(ransack `auth_object`), `app/controllers/memberships_controller.rb`,
`app/views/people/show.html.erb`, `app/views/people/_form.html.erb`,
`app/views/people/index.html.erb` (Age sort guard),
`config/initializers/features.rb`,
`config/initializers/filter_parameter_logging.rb`, `config/routes.rb`,
`app/models/hook.rb` (catalog), `db/seeds.rb`. Phase 3 adds
`app/models/checkin_field.rb` and the events/checkins views.

---

## 13. Decisions and open items

### 13.1 Still open (deferred, not blocking)

1. **Badge-refined narrowing.** "Only YPT-certified leaders" (require a badge on
   top of a level, an AND) is not in v1. If needed, add
   `required_badge_id` on `PersonField`, applied to the `leaders` component
   only. This is the opposite direction from badge grants (§3.3), which only
   add access.
2. **Confidential-at-rest and read logging** (§7, §8).
3. **People-directory narrowing** (§1.1). Separate change.
4. **Family registration** (§14). Separate branch, still being designed.
5. **`guardianship - expired` hook** (§8.1), if an integration needs it.

### 13.2 Resolved in this revision

| Question | Decision |
|---|---|
| Does this change existing profile fields? | Yes. All seven built-ins (including email) become system fields (§6), defaulting to today's behavior, with a one-click recommended preset |
| Can fields be added to the profile? | Yes, by section and position; `show_on_profile` allows internal-only fields |
| Admin UX | Fully specified (§10): index/matrix, form with type options and badge access, sections, archive/restore/delete, Preview as…, recommended preset, roster |
| Security groups? | No new group concept. Relative audiences (self, guardians, leaders, direct teammates) plus **admin-assigned badge grants** as fixed audiences, scoped by the badge's team |
| Which relationships grant access? | Only types an admin marks `guardianship: minor` or `consented`, parent side → child side (§3.4). Any other relationship grants nothing |
| Adult students | `minor` guardianship can expire at a configurable age (off by default); an adult grants access back with a `consented` relationship they create |
| Telling users who can see a field | `audience_for` plus viewer-relative messages (§4.5); fields the viewer can't read are never hinted at |
| Hooks | §8.1: CRUD hooks on the new definition, value, and grant tables plus `relationship_types`, and a unified `person_fields - value changed` event |
| `team` level matching everyone | Fixed: direct memberships, not `all_teams` (§3.3) |
| Should the subject always see their own field? | No: `guardians` excludes the subject |
| Assistant leaders who aren't managers | Badge grants, scoped to the team (no new membership role) |
| Transitive family (grandparents) | Not included; guardianship is direct edges only. A grandparent with custody gets their own guardianship relationship |
| Can parents edit a child's field? | Yes, if they can write it; `update?` widens and the base profile stays at today's rule (§4.2) |
| Value deletion on archive/re-scope | Never. Only on field destroy (§3.2) |
| Write broader than read | Invalid, as with `Page` (§3.3) |

---

### 13.3 Implementation notes (phases 0 and 1)

Where the build differs from the text above, or settles something the text
left open:

- **Evaluator.** `PersonFieldAccess` (one object per viewer and subject)
  holds the logic from §3.3, so the guardian, leader, and teammate lookups
  run once per pair rather than once per field. `PersonField#readable_by?`,
  `#writable_by?`, and `#access_for` delegate to it. The §3.3 sketch returned
  `:system_read_only` (truthy) for writes to email, and checked admins first;
  the build returns nil for those writes, for admins too.
- **Guardians can open their wards' profiles.** `PersonPolicy#show?` and its
  scope now include `viewer.wards`. Without this, a parent who isn't on a
  team couldn't open their child's profile at all, so `family` and
  `guardians` fields were unreachable for them.
- **Badge access on the field form** is one *None / Can see / Can see and
  edit* select per admin-assigned badge (`PersonField#badge_access=`), not
  add/remove rows. No JavaScript is needed, and the full set of badges that
  could grant access is visible at a glance.
- **Member Info** is open to every signed-in user and says "There are no
  fields you can view for anyone" when that's true. `NavItem` has no
  visibility hook, so the nav link shows whenever the feature is on.
- **Messages** live in `config/locales/person_fields.en.yml` (a new file)
  rather than `en.yml`. "Ends soon" means within 90 days. The field form
  updates each level's description as it changes; there's no separate
  summary-sentence preview.
- **Booleans.** An unchecked box clears the value, so "never set" and "no"
  are the same and show as "No".
- **Deleting a team** that a field applies to fails (the foreign key
  restricts it). Re-scope or delete the field first. Worth a friendlier
  error later.
- **Phase 2** (done): `Person.ransackable_attributes` fails closed for a
  nil `auth_object`, so ransack through an association only reaches details
  everyone can see. Resubmitting a stored value is not a change, so legacy
  data that wouldn't pass a field's validation (a free-text phone number,
  say) never blocks saving a profile. "Person Fields" and "Person Field
  Sections" moved to the always-on People setup section, because system
  fields are enforced with the feature off. `db/seeds.rb` calls
  `ensure_system_fields!`, since a fresh database loads the schema rather
  than running the data migration.

- **Phase 3** (done): a check-in field's link to a person field can only be
  set when it's created, so linking never orphans collected responses, and a
  person field used by a check-in field can't be deleted. The arrange page
  leaves out linked fields (there's nothing to drag) and responses the
  viewer can't see. The print sheet groups people whose value the viewer
  can't see under "—". The check-in form hides responses the editor can't
  see, even when they could write them. `PersonField.level_people` exposes a
  level's audience for check-in field read levels.

Open questions:

1. ~~Who can delete a `minor` guardianship.~~ Resolved: managers and admins
   only (§3.4).
2. ~~`verify_authorized` on `InternalController`~~ Resolved: its own fix
   branch, `feature/enforce-authorization`.

## 14. Related: family registration (separate branch, in design)

Not part of this feature. Recorded here because person-fields' guardianship
model depends on its rules, and so the requirements agreed so far aren't lost.
It gets its own branch (`feature/family-registration`, depending on
`feature/person-fields`) and its own spec.

Agreed so far:

1. **Guardians can only create new people, never claim existing ones.** "Add
   a family member" creates a new `Person` and a `minor` guardianship
   relationship to the creator in one step. This is the single exception to
   "guardianship types are admin/manager-created" (§3.4), and it's safe
   because a brand-new record exposes no one else's data. Linking an existing
   person still requires a leader or admin.
2. **Duplicate detection before creating.** Before the record is saved, the
   submitted details are checked against existing people, as well as we can:
   normalized email (against `users.email`), normalized phone (digits only),
   birthday plus last name, and birthday plus normalized first name. On a
   likely match the record is **not** created. The guardian sees a generic
   message: "We believe this person may already be registered. Please contact
   your leader to confirm." The message never reveals who matched, which team
   they're on, or which detail matched, so the form can't be used to look
   people up. The attempt is recorded for leaders and admins to follow up.
3. **Fix `PersonPolicy#create?`.** Today any signed-in user can
   `POST /people`; the family flow replaces that with explicit rules.
4. **Hooks** (per the project rule): at least `family registration - possible
   duplicate`, so an integration can notify a leader. The rest is to be
   decided with the spec.
5. **Team membership** still goes through a membership application and leader
   approval. Creating a child doesn't put them on a team.

Open for discussion: the exact matching rules and thresholds, what a leader
sees and does when following up a possible duplicate (merge, link, or
dismiss), whether an adult can use the same flow, and rate limiting.

