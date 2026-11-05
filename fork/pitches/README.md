# Feature descriptions

Short functional descriptions of features, built or proposed: what each
one does, the problem it solves, how big the change is, and how it could
be adopted. Each is written against the fork, so upstream can adopt one
along with the features it depends on. Bugs and small tasks go in the
backlog instead. Full specs, where they exist, are separate.

| # | Feature | In one line | Size | Spec |
|---|---|---|---|---|
| 1 | [Search and add](01-search-and-add.md) | Add people to badges, teams, and events from a live search panel, without a form page per addition | Small. No migrations, no flag | None |
| 2 | [Time kiosk improvements](02-kiosk.md) | Close the kiosk's security holes, then optional one-scan clock-in, return to Welcome, and limits on who can open it | Small. No migrations; settings default to current behavior | Kiosk spec, §1–5 |
| 3 | [Person fields with permissions](03-person-fields.md) | Admin-defined profile fields, each with its own read and write levels, including guardians | Large. About 40 upstream files, 7 migrations, flag off by default | Person fields spec |
| 4 | [Forms](04-forms.md) | Ask a group for information or a signature by a deadline, and track who has answered | Medium, mostly new files. Requires person fields | Forms spec |
| 5 | [Sign-ups and commitments](05-signups.md) | Let people claim shifts and items at events, and track what each person or family owes from check-ins and sign-ups | Large, mostly new files: 16 migrations, 5 upstream files, flags off by default. Requires extension registries (4 more upstream files) | Sign-up sheets and commitments spec |
| 6 | [MCP server](06-mcp-server.md) | Let a member's AI client read and change GatherPack data, signed in as that member and within their permissions | Medium, mostly new files. One migration; 2–3 upstream files; flag off by default. Requires the OAuth provider | [MCP server spec](../specs/mcp-spec.md) |
| 7 | [Theming and a modern skin](07-theming-and-modern-skin.md) | Pick a brand color and logo and get a consistent, modern look and sign-in page, with page markup and logic unchanged | Medium, mostly new files. Two migrations; 6 upstream files; flags off by default | [Modern skin spec](../specs/modern-skin-spec.md) |
| 8 | [My GatherPack](08-my-gatherpack.md) | Organize the app around what each person needs to do: a to-do home, a menu per person, a family view, and phone versions of the top tasks | Medium to large, in independent parts. No migrations expected; a few upstream files; flag off by default. Follows the modern skin | [My GatherPack spec](../specs/my-gatherpack-spec.md) |
| 9 | [App feel](09-app-feel.md) | Smooth page changes, saves that keep your place, home-screen install, and phone notifications, all on the existing Hotwire stack | Small to medium, in independent parts. One migration, for notifications; a few upstream files; flags off by default | [App feel spec](../specs/app-feel-spec.md) |

## How they relate

Search and add and the kiosk changes are independent of everything else.
Person fields changes core behavior, and forms is built on it (its
permission levels, guardianship, and field types). Without person fields
in core, forms would move onto whatever equivalent exists.

Sign-ups and commitments are independent of person fields and forms, and
of each other: either can be adopted alone, and a small third part
connects them when both are present. A sheet position can require a
form by requiring the badge the form grants on completion. Both need the
extension registries below.

## Extension points that would help any plugin

Several features edit upstream files only to add a menu item, a tab, or a
hook event. These small, generic extension points would remove those
edits:

- **Hook event and setting registration**, instead of the fixed
  `Hook.catalog` and `lib/settings.rb` lists. Built as extension
  registries; sign-ups and commitments use it.
- **Feature routes**, by enabling the commented-out `routes_proc` loop in
  `config/routes.rb`.
- **Slots on `GatherPack::Feature`** for dashboard cards, profile tabs,
  and event page panels.
