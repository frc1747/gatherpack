# BL-092: Sorting or searching the Shortcuts list shows an error page

| | |
|---|---|
| Kind | upstream bug |
| Priority | medium |
| Status | not started |
| Added | 2026-11-28 |
| Upstream base checked | `3d5ce8f96` |
| Planned branch | `feature/shortcuts-ransack` (from `upstream/main`) |
| Upstream issue / PR | none yet |

## Summary

The Shortcuts list has a **Sort By > Last Updated** menu. Choosing it gives the person an error page (500). So does any search the list's filter form would send. Ransack refuses to sort or filter a model that doesn't say which attributes may be searched, and `Shortcut` says nothing.

Every role in the ZAP scans of Ditto hit it (886 errors across the scans). It was checked on Ditto directly: `Shortcut.ransack(s: "updated_at desc").result.to_a` raises `RuntimeError: Ransack needs Shortcut attributes explicitly allowlisted as searchable`. An empty search works, so the list shows until someone sorts it.

## Where things are (upstream `3d5ce8f96`)

- `app/controllers/shortcuts_controller.rb:6`: `policy_scope(Shortcut).ransack(params[:q])`.
- `app/views/shortcuts/index.html.erb`: `search_form_for @q` and `sort_link @q, :updated_at`.
- `app/models/shortcut.rb`: no `ransackable_attributes` (other list models define it).

## Proposed fix

`Shortcut.ransackable_attributes`: return the columns the list shows and sorts by (`name`, `url`/path, `updated_at`, `created_at`), as the other list models do. `ransackable_associations` returns `[]`.

## Tests

- Request spec: a member who can see Shortcuts GETs `/shortcuts?q[s]=updated_at+desc`: 200, list in that order.
- Request spec: `/shortcuts?q[name_cont]=x` returns 200; `/shortcuts?q[not_allowed_eq]=x` returns 200 (ignored), not 500.

## Fork strategy notes

Upstream file edit (`shortcut.rb`): list it in `FORK.md` "Upstream files touched". A plain bug fix; confirm with Corey before any issue or PR.
