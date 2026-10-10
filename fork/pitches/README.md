# Feature descriptions

Short functional descriptions of the major features: what each one does,
the problem it solves, how big the change is, and how it could be
adopted. The full specs are attached separately as an appendix.

| # | Feature | In one line | Size | Spec |
|---|---|---|---|---|
| 1 | [Search and add](01-search-and-add.md) | Add people to badges, teams, and events from a live search panel, without a form page per addition | Small. No migrations, no flag | None |
| 2 | [Time kiosk improvements](02-kiosk.md) | Close the kiosk's security holes, then optional one-scan clock-in, return to Welcome, and limits on who can open it | Small. No migrations; settings default to current behavior | Kiosk spec, §1–5 |
| 3 | [Person fields with permissions](03-person-fields.md) | Admin-defined profile fields, each with its own read and write levels, including guardians | Large. About 40 upstream files, 7 migrations, flag off by default | Person fields spec |
| 4 | [Forms](04-forms.md) | Ask a group for information or a signature by a deadline, and track who has answered | Medium, mostly new files. Requires person fields | Forms spec |

## How they relate

Search and add and the kiosk changes are independent of everything else.
Person fields changes core behavior, and forms is built on it (its
permission levels, guardianship, and field types). Without person fields
in core, forms would move onto whatever equivalent exists.

## Extension points that would help any plugin

Several features edit upstream files only to add a menu item, a tab, or a
hook event. These small, generic extension points would remove those
edits:

- **Hook event registration**, instead of the fixed `Hook.catalog` list.
- **Feature routes**, by enabling the commented-out `routes_proc` loop in
  `config/routes.rb`.
- **Slots on `GatherPack::Feature`** for dashboard cards, profile tabs,
  and event page panels.
