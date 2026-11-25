# BL-062: Screen kit: shared partials for the screen standard

| | |
|---|---|
| Kind | fork-only (screens) |
| Priority | high |
| Status | done (feature/screen-kit, not yet released) |
| Added | 2026-11-21 |
| Commit checked | `hbr/integration` @ `c4700b175` |
| Planned branches | new `feature/screen-kit` from `upstream/main`; manifest: right after `feature/search-and-add` |
| Upstream issue / PR | none |

## Summary

Every fix-up item (BL-063 to BL-073) rearranges a feature's screens into the same shapes: a header card with a state line, an action row with a More menu, an inline question above Save, a filter bar, a people table. Build those pieces once, as partials and a small helper, so features use them instead of near-copies. Also restyle upstream's yellow Cancel as grey through CSS, behind a flag, so Edit and Cancel stop sharing a colour. Design: `fork/specs/screen-standard-spec.md` "Screen kit".

## Evidence

At `hbr/integration` `c4700b175`: no More menu exists anywhere (0 of 32 dropdowns hold actions); action rows are built three ways (`card-footer`, `.actions`, closing `d-flex gap-2`); Cancel is `btn-warning` in 112 forms, the same as Edit; status filters are written per feature (`forms/_team_filter`, `forms/show.html.erb:22-28`, `checklists/show.html.erb:50-57`, `signup_sheets/roster.html.erb`).

## What it does

Partials in `app/views/shared/` (locals as in the spec): `_page_header`, `_state_line`, `_action_row`, `_inline_confirm`, `_filter_bar`, `_people_table`, `_empty_state`, `_record_tabs`.

- `_action_row` takes a list of actions, shows up to three, and puts the rest in **More** (`btn btn-secondary dropdown-toggle`, Bootstrap dropdown, right-aligned). Destructive actions (`destructive: true`) go last in More with `text-danger`; when there are three actions or fewer and no More, Delete is the last button (`btn-danger`). At phone width only the first action and More show; the hidden ones appear in More (`d-md-none` items). POST/DELETE actions render as `button_to` inside the menu (`dropdown-item`), with `turbo_confirm` when given.
- `_state_line` renders muted text and an optional link ("Start taking answers").
- `_inline_confirm` renders the question and radio choices; the caller's controller reads the param.
- `_filter_bar` renders the team select, status pills with counts (`btn-sm`, active `btn-secondary`, others `btn-outline-secondary`, as `forms/show` does), a "More choices" `<details>`, and table actions at the right.
- `_people_table` wraps in `table-responsive`, links Person, and shows the empty line.

Helper `app/helpers/screen_kit_helper.rb`: `screen_action(label, path, style: :secondary, method: :get, confirm: nil, visible: true, destructive: false)` returns a `ScreenKit::Action` (a `Data` struct in `app/models/screen_kit/action.rb`); `state_line(text, link_text: nil, link_path: nil)`.

Stylesheet `app/assets/stylesheets/screen_kit.css`, linked only while `feature_screen_standard` is on (setting registered in `config/initializers/screen_kit.rb`, label "Standard buttons on built-in screens", default off): a Cancel link takes `btn-secondary`'s colours through the `--bs-btn-*` variables. One selector, the same as the spec's: `main form .card-footer > a.btn-warning:has(+ [type=submit])`, a yellow link directly before the submit, which is Cancel's place in upstream's forms. Other yellow links in a footer with a submit (Edit beside "Search Messages" in `mailboxes/show.html.erb:27-32`) keep their colour. No table rule: every bare table found is a fork view, fixed in its own item.

## Tests

- Helper/partial tests: three actions show three buttons and no More; five show two plus More holding three, Delete last; a `visible: false` action is left out; a destructive action with a confirm renders `button_to` with `data-turbo-confirm`.
- `_state_line` with and without a link; `_inline_confirm` selects the default; `_people_table` empty state.
- System test at phone width: only the first action and More are visible; More holds the rest.
- Flag: `screen_kit.css` is linked only with `feature_screen_standard` on; with it on, an upstream edit page's Cancel computes to the secondary colour (system test on `badges/edit`), and Edit on `mailboxes/show` keeps `btn-warning`'s colour (system test).

## Fork notes

- Upstream files touched: one line in `app/views/layouts/application.html.erb` to render the flag's stylesheet partial (as `feature/pinned-form-buttons` does); placed away from other fork lines and checked by a trial merge. Record it in FORK.md.
- Every later fix-up item depends on this branch. It sits right after `feature/search-and-add` in the manifest (depends only on `upstream/main`); each fix-up merges it into the feature branches it changes.
- Update the `fork-spec` "Screen design" line that says to write the same markup until the kit is in the base, once it is.
