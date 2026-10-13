# BL-023: Emergency contacts without guardian powers

| | |
|---|---|
| Kind | upstream feature |
| Priority | low |
| Status | waiting |
| Added | 2026-10-13 |
| Feature branches checked | `feature/person-fields` at `c050087` |
| Planned branch | decide after step 1; probably on `feature/person-fields` |
| Upstream issue / PR | none |

## Summary

The likely misuse of guardianship (BL-022) is to make someone like an emergency contact "show up": flag the type, and the contact appears in the right places, but they can also see and edit the child's family-level fields, fill in forms, and sign consent. An emergency contact needs the opposite: they get no access, and the people looking after the child (leaders, and the child's guardians) can see who the contact is and how to reach them.

Decided with Corey (2026-10-13): if this is needed, make a weaker kind of relationship rather than stretching guardianship.

## Step 1: check what a plain relationship already does

A relationship type with guardianship "None" may already be most of this. Check against current `upstream/main` + `feature/person-fields`, and write down:

- Who sees a relationship on the child's Relationships tab (`app/views/people/relationships.html.erb`), and whether a leader who manages the child, but not the contact, can see the contact's name.
- Whether that leader can open the contact's profile or phone number. `PersonPolicy` scope (`app/policies/person_policy.rb:7,13`) allows teammates and wards, so a contact outside the team is probably hidden.
- Whether the contact sees anything new about the child (they shouldn't).

If leaders can already see the contact's name and number, this item is just guidance: "use a type with no guardianship" (BL-022's hint) and close it.

## Step 2: if something is missing

The smallest change that fits:

- A per-type setting "Show contact details to people who can see the child" (default off). When on, the child's Relationships tab shows the other person's name, phone and email to anyone who can see the child, without giving them access to the other person's profile.
- No new powers for the contact side, no forms, no reminders.
- Prefer a column on `relationship_types` (new migration) over another guardianship enum value, so guardianship stays a yes/no question about powers.

## Tests

- A leader sees a contact's name and phone on a child they manage; they can't open the contact's profile if they couldn't before.
- The contact sees nothing new about the child.
- Guardianship behavior is unchanged.

## Fork strategy notes

Relationships are upstream; the guardianship enum is ours (`feature/person-fields`). If step 2 is needed, it's a small upstream-shaped change: keep `Hbr` out of names. Confirm with Corey before any upstream issue.
