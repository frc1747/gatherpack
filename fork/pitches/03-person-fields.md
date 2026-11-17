# Person fields with read and write permissions

## Summary

Admin-defined profile fields, each with its own read and write level,
plus guardianship so parents can see and edit their children's data. The
built-in profile fields come under the same controls. This is a
field-level permission layer for `Person` data in core; the design is
one way to build it.

## Problem

Teams keep sensitive information about members: allergies, medical
notes, emergency contacts, photo releases. Profile fields are
all-or-nothing today. Anyone who can see a profile sees every field on
it, and under one root team that is effectively everyone. Values also
leak through search and sorting (searching people by dietary
restrictions for "peanut" finds them even where the page hides the
field), the calendar's birthdays, and event print sheets.

The need is need-to-know: a student's medical note visible to the
student, their guardians, their team's leaders, and a designated role
such as a health officer, and not to other students, other parents, or
unrelated leaders. Guardians also can't edit a child's profile today.

## What it does

- **Custom fields.** Admins add fields (text, yes/no, date, number,
  choice, multiple choice, phone, email) under Setup, with no code
  changes. Fields can be grouped into sections and limited to one team and
  the teams below it.
- **Read and write levels per field:** admin only, the person, leaders,
  the person and leaders, guardians, family, teammates, or everyone.
  Write can never be broader than read.
- **Badge grants.** A badge can grant access to a field, for example
  "Health Officer" holders reading the medical field for everyone.
- **Guardianship.** A relationship type can be marked as guardianship.
  Guardians can then see and edit their child's fields as each field
  allows. Optional age settings end guardianship at adulthood.
- **Built-in fields included.** Phone, address, birthday, dietary
  restrictions, shirt size, gender, and email become system fields with
  the same controls. Upgrading changes nothing: they start at today's
  behavior (everyone reads; the person and leaders write) until an admin
  tightens them.
- **Every read path covered:** the profile, search, sorting, calendar
  birthdays, event check-ins and print sheets, and logs (values are
  filtered). The API exposes no field values.
- **Preview as…** shows a profile as a chosen person would see it. Fields
  also explain their reach relative to the viewer (to a guardian: "Alex
  can see this but can't change it").
- **Event check-in fields** can link to a person field and get their own
  read level.
- **Hooks** for field and value changes.

## How it's built

- Four new tables (field definitions, values, sections, badge grants) and
  a guardianship column on relationship types. Seven reversible
  migrations; one seeds the system fields.
- Modeled on the existing check-in fields (definition plus value rows) and
  the existing Page permission levels.
- Behind a feature flag, off by default.
- **Footprint:** about 40 existing upstream files. The change is
  cross-cutting by nature: every place that shows, searches, or saves a
  profile value has to go through the permission check, or values leak.

## Why it can't be a plugin

The plugin registry (`GatherPack::Features`) adds menu entries, Setup
links, and toggles. That suits add-ons such as forms. This feature
changes how core reads and writes `Person` data, so it lives in core or
not at all.

## Adoption

The decision on direction matters more than the code. Options:

1. **This design, in pieces:** guardianship, then custom fields with
   permissions, then system fields, then events.
2. **A different design** for field-level permissions; existing data can
   be migrated onto it.
3. **Not in core.** Small generic extension points still reduce the cost
   of keeping it outside: hook event registration, feature routes, and
   slots for dashboard cards, profile tabs, and event page panels.

Open in the spec: badge-refined narrowing (e.g. only leaders with a given
certification), encrypting sensitive values at rest, and logging who read
a field.
