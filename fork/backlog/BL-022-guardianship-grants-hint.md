# BL-022: Say what guardianship grants, where it's set

| | |
|---|---|
| Kind | upstream feature |
| Priority | medium |
| Status | waiting |
| Added | 2026-10-13 |
| Feature branches checked | `feature/person-fields` at `c050087`, `feature/forms` at `b9a6efe` |
| Planned branch | change on `feature/person-fields`, plus one initializer line on `feature/forms` |
| Upstream issue / PR | person-fields is issue #489; nothing for this yet |

## Summary

Guardianship is one setting on a relationship type ("None", "Guardian while the child is a minor", "Guardian with the child's consent"), and the type's labels are free text. Whoever is on the parent side of a flagged type is a guardian everywhere, whatever the type is called. Across the fork that one flag now grants:

- **Profile:** see the child in the people list and their profile; see and edit person fields at family or guardian levels (`feature/person-fields`).
- **Forms:** fill in forms for the child where the respond level includes guardians; **sign guardian and guardian-if-minor consent questions**; get Remind emails, with the guardian message (`feature/forms`, BL-021).

The relationship type form mentions only the profile fields. An admin who flags "Emergency contact" or "Mentor of" so those people "show up" would also let them sign permission slips. In production on 2026-10-13 only "Parent/Guardian ↔ Student" is flagged (80 relationships), so nothing is wrong yet.

Decided with Corey (2026-10-13): keep "guardian" as the one name everywhere (don't use each type's label in emails or screens); make the flag's consequences visible where it's set. A weaker "contact" kind of relationship is BL-023.

## Where things are

`feature/person-fields` `c050087`:
- `app/views/relationship_types/_form.html.erb:8-9`: the guardianship select; its hint names only profile fields.
- `app/models/relationship_type.rb:9-13`: `GUARDIANSHIP_LABELS`; `:37-41` the minor-guardianship permission check.
- `app/policies/person_policy.rb:7,13`: wards are visible to their guardians.
- `app/models/audience_levels.rb:48`: the `:guardian` component is `viewer.wards`.
- `app/views/relationship_types/_relationship_type.html.erb:4-5`, `show.html.erb:8`: where flagged types show "Guardian".

`feature/forms` `b9a6efe`:
- `app/models/form_access.rb:104-113`: `signer_roles`, where guardians sign.
- `app/services/form_reminder_sender.rb`: guardians get reminders.

## Proposed fix

1. Replace the hint with a short list of what a guardian can do, shown under the select, and on the type's show page when it's flagged:
   > Guardians can:
   > - see the child's profile and fields set to family or guardian levels, and edit them
   > - fill in forms for the child and sign consent as their guardian
   > - get form reminders about the child
   >
   > Don't use guardianship just to link people. For an emergency contact, use a type with no guardianship.
2. Keep the list extensible without making features edit the view: `RelationshipType::GUARDIAN_GRANTS` holds person-fields' lines, and `feature/forms` appends its two lines from its own initializer (`config/initializers/forms.rb` or the features initializer). That way each feature describes its own powers and the view never conflicts. If BL-018's registries fit better (`GatherPack::Features`), use them instead.
3. When changing an existing type from None to a guardianship (or back) that already has relationships, add a confirmation that names the count: "This makes the parent side of 80 relationships guardians."

## Tests

- The type form lists person-fields' grants; with forms loaded, the forms lines too.
- The show page lists them only for flagged types.
- Changing a type with relationships from None to minor asks for confirmation naming the count; a new type doesn't.

## Fork strategy notes

The view and constant are on `feature/person-fields` (an upstream candidate, so keep the wording generic). The forms lines go on `feature/forms` in its own initializer, not in the shared view. Related: BL-021 (Remind's guardian handling), BL-023.

## Related config (not part of this item)

The Guardianship Age Limit was set to 18 in production on 2026-10-13. It changes nothing yet: 46 of the 47 students with a guardian link have no birthday on file, and "End Guardianship Without a Birthday" is off, so their links stay active. Birthdays also decide who signs guardian-if-minor questions; with no birthday, a guardian signs. Filling in birthdays is what makes both work.
