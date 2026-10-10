# Spec: Dashboard Widgets

Status: built 2026-10-06 (v1). Branch `feature/widgets`, based on `upstream/main`.

## 1. Goal

Let an admin add small, titled sections ("widgets") to the dashboard without a code change. A widget is like a Page that lives on the dashboard: it has a title and content, can use ERB, can bring its own CSS and JavaScript, and is shown only to the people it is meant for.

Examples this must handle:

- **Kickoff countdown.** Days, hours and minutes until a date, ticking live. JavaScript and CSS, no ERB.
- **Who's clocked in.** The live roll call that today is a Page, shown on mentors' dashboards and refreshed every minute. ERB, visible to a subset of people.
- **Plain notices.** A Markdown block such as "Shop hours this week".

### 1.1 Non-goals (v1)

- People hiding, reordering or adding widgets to their own dashboard. Admins arrange the dashboard for everyone.
- Team managers authoring widgets. Admins only (see 5).
- Replacing the built-in dashboard cards (Forms to complete, Shortcuts, Announcements, Calendar, Ledgers). Widgets sit alongside them.
- Widgets anywhere other than the dashboard (team pages, event pages). The rendering is built so this could come later.
- A widget library or marketplace.

## 2. What exists today (and what we reuse)

| Piece | Where | Use |
|---|---|---|
| Pages with optional ERB | `Page`, `PagesHelper#format_page_content` | Same content model: Markdown by default, ERB when `dynamic` is on. Same rule: only architects can turn ERB on. |
| Page viewer levels | `Page::PERMISSION_LEVELS`, `PagePolicy#show?` | Same visibility levels and team, minus `public` (the dashboard needs sign-in). |
| Theme | `Theme#css_variables`, `Theme#custom_css`, `layouts/_theme_styles` | Widgets inherit it by default. CSS variables still reach widgets that replace the stylesheet (see 4.3). |
| Feature registry | `GatherPack::Features`, `config/initializers/features.rb` | Register `:widgets` as a toggleable feature with a "Widgets" link in the side nav's Content section, like Pages. The toggle is the runtime flag, stored in `Settings`, default off. |
| Hooks | `CanBeHooked`, `Hook.catalog` | `widgets - create/update/destroy`. |
| Code editor | `app/javascript/code_editor.js` | Used for the content, CSS and JavaScript fields. It has no CSS or JavaScript mode, so those fall back to its Ruby highlighting, which reads well enough. |
| Dashboard | `welcome/dashboard.html.erb` | Two columns (`col-lg-6`). Widgets render at the top or at the end of either column. |

Upstream has no dashboard extension point, so this branch is also the "dashboard card slot" seam we wanted to offer upstream.

## 3. Data model

### 3.1 `widgets`, neat_id prefix `wdg`

| Column | Type | Notes |
|---|---|---|
| `title` | string, required | Shown as the card header. |
| `show_title` | boolean, default true | Off for widgets that draw their own header (a countdown banner). |
| `content` | text | Markdown, or ERB when `dynamic`. May be blank if the widget is all JavaScript. |
| `dynamic` | boolean, default false | Parse `content` as ERB. Only architects can set it, as with Pages. |
| `stylesheet` | text | Optional CSS. |
| `style_mode` | string, default `theme` | `theme`: widget CSS adds to the app and theme styles. `replace`: only the widget CSS applies (see 4.3). |
| `javascript` | text | Optional JavaScript. Only architects can set it. |
| `refresh_seconds` | integer, default 0 | Reload the widget body this often while the dashboard is on screen. 0 = never. Minimum 15 when set. |
| `placement` | string, default `right` | `top` (full width above both columns), `left`, `right`. |
| `position` | integer, default 0 | Order within the placement, lowest first. Ties by title. |
| `viewer` | string, default `user` | `user`, `team`, `manager`, `admin`, as in Pages. |
| `team_id` | uuid, optional | Required for `team` and `manager`. |
| `enabled` | boolean, default true | Off hides the widget without deleting it. |
| timestamps | | |

Model: `has_neat_id :wdg`, `include CanBeHooked`, `has_paper_trail versions: { class_name: "AuditLog" }`, `belongs_to :team, optional: true`. Ransackable `title`, `placement`, `enabled`, `updated_at`.

Validations mirror Page: `viewer` in the levels, `team` present for `team`/`manager`, `style_mode` and `placement` in their lists, `refresh_seconds` 0 or >= 15.

Why a new table and not a flag on `pages`: a widget needs fields a Page doesn't (placement, CSS, JS, refresh), and editing `Page` touches upstream code that both Pages and Forms depend on. A new model is all new files.

## 4. Rendering

### 4.1 Layout

`dashboard.html.erb` gets three one-line renders: `render "widgets/slot", placement: :top` above the row, and `:left` / `:right` at the end of each column. The partial does its own query (`policy_scope(Widget).enabled.where(placement:).order(:position, :title)`), so `WelcomeController` is unchanged. The partial renders nothing when the feature is off.

### 4.2 Each widget is a card with a Turbo Frame body

```erb
<div class="card widget" id="<%= dom_id widget %>">
  <div class="card-header"><h2><%= widget.title %></h2></div>   <%# omitted when show_title is off %>
  <%= turbo_frame_tag widget, src: body_widget_path(widget) %>
</div>
```

`WidgetsController#body` (`GET /widgets/:id/body`) renders just the body, with no layout. `show` is an admin preview page that renders the same card. The card starts hidden and appears once its body loads with something in it. Loading the body separately gives us:

- **Isolation.** A widget whose ERB raises shows "This widget couldn't be shown" (and the error, to admins) instead of breaking the dashboard. Pages today only rescue `SyntaxError`; widgets rescue `StandardError`.
- **Speed.** A slow ERB widget doesn't hold up the dashboard.
- **Refresh.** `refresh_seconds` reloads the frame, only while the tab is visible, instead of reloading the whole page as the clocked-in Page does now.
- **Preview.** The widget's page shows the same card, so an admin sees it alone.

**Hiding itself.** If a dynamic widget's ERB renders nothing but whitespace, or a widget has no content and no JavaScript, the card stays hidden. ERB can then decide visibility beyond the viewer levels. The clocked-in widget needs this: "managers of Students, or members of Student Leadership" can't be expressed as one level and team.

### 4.3 Styles

`style_mode: theme` (default). The body renders in the normal DOM, so Bootstrap, the theme variables and the theme's custom CSS all apply. The widget's CSS is wrapped in a CSS nesting block scoped to the widget, so it can't leak onto the rest of the dashboard:

```css
[data-widget="wdg_abc123"] {
  /* widget stylesheet here; & is the widget body */
}
```

`style_mode: replace`. The body renders inside a shadow root, so no app, Bootstrap or theme rules reach it; only the widget's CSS applies. CSS custom properties and inherited properties (font, color) still cross the shadow boundary, so a replacing stylesheet can follow the theme by writing `color: var(--bs-primary)` and so on. This is what "completely overridden, but obeys the theme by default" means in practice: theme is the default mode, and even replace mode can use the theme's values.

The shadow root is attached by the Stimulus controller (4.4), not with declarative `<template shadowrootmode>`, because Turbo frame updates insert HTML with methods that ignore declarative shadow roots.

### 4.4 JavaScript

Two new Stimulus controllers. `widget_card_controller.js` sits on the card: it unhides the card when the body loads with content and runs the refresh timer. `widget_controller.js` sits on each widget body. On connect it:

1. Attaches the shadow root and moves the body into it, for `replace` mode.
2. Runs the widget's JavaScript as the body of a function: `new Function("root", "widget", code)`. `root` is the element (or shadow root) holding the widget body, so code finds its own elements with `root.querySelector(...)` and never collides with another widget. `widget` gives `{ id, title, refresh() }`.
3. If the code returns a function, keeps it as cleanup.

On disconnect (navigating away, or the frame reloading) it calls the cleanup. Without this, a countdown's `setInterval` would keep running after Turbo leaves the dashboard and stack up each time someone comes back.

ERB passes data to JavaScript through the markup, for example `<div data-kickoff="<%= kickoff.iso8601 %>">`, which the code reads from `root`.

The JavaScript is stored on the widget and sent in a data attribute on the body, not as an inline `<script>`, so it runs exactly once per connect whether the body came from a full page load or a frame reload. GatherPack sets no Content Security Policy today; if one is added it will need to allow this (`unsafe-eval`, or a nonce scheme).

## 5. Permissions

| Action | Who |
|---|---|
| See a widget | Signed-in users who pass its `viewer` level and team, same rules as `PagePolicy#show?`. Admins see all. Disabled widgets are hidden from everyone on the dashboard; admins can still preview them. |
| List widgets, open a widget's page | Like Pages: everyone signed in, limited to the widgets they can see. |
| Create, edit, delete, reorder | Admins. |
| Set `dynamic` or `javascript`, or change the content of a dynamic widget | Architects only. The fields are dropped from params for everyone else, and are shown as read-only text to admins who aren't architects. (The code editor ignores Rails' `readonly`, so a locked field is a `<pre>`, not an editor.) |
| Set `stylesheet` | Admins (they can already edit the theme's custom CSS). |

ERB runs Ruby on the server and JavaScript runs in every viewer's session, so both stay with architects. This is stricter than Pages, where any admin can edit the content of a dynamic page. It isn't a hard wall: Markdown passes raw HTML through, so an admin can still put markup (and a `<script>`) in a non-dynamic widget, as they already can in a Page or the theme's custom CSS.

`WidgetsController#body` checks the policy itself, so a widget's body can't be fetched by someone who couldn't see the card.

## 6. Managing widgets

Side nav → Content → **Widgets** (`/widgets`), next to Pages (changed from a Setup link on 2026-10-06: Corey wants it to flow like Pages). The index lists the widgets the viewer can see, grouped by placement in display order, with who can see each one, its team and whether it's shown. Each title opens the widget's page, which previews it. Admins also get New, Edit and Delete. The form, top to bottom:

- Title, Show title
- Where on the dashboard (Top / Left column / Right column), Order
- Who can see it (viewer level), Team
- Content (code editor, Markdown or HTML; ERB when enabled)
- Style: "Use the theme" / "Replace all styles", and the CSS editor
- JavaScript (architects)
- Refresh every N seconds
- Enabled

Directions at the top of the form: "A widget is a titled section on everyone's dashboard. Choose where it goes and who sees it, then write its content. If the content is blank for someone, they won't see the widget."

## 7. Feature flag

Registered in `config/initializers/features.rb`:

```ruby
GatherPack::Features.register_built_in(
  GatherPack::Feature.new(
    key: :widgets,
    label: "Dashboard Widgets",
    description: "Custom sections on the dashboard",
    default_enabled: false,
    nav_section: "Content",
    nav_position: 30,
    nav_items: [ GatherPack::Feature::NavItem.new(label: "Widgets", path: :widgets_path, icon: "table-cells-large") ]
  )
)
```

Toggleable, default off. When off the dashboard renders as before and `/widgets` redirects home with "Dashboard widgets are turned off". The routes are always drawn (as Forms does), so tests can switch the feature on with `with_settings`.

## 8. Upstream files touched

New files: model, migration, policy, controller, views, helper, breadcrumbs, two Stimulus controllers, tests, and `test/support/settings_test_helper.rb` (byte-identical to the copy on `feature/person-fields`, so the two merge cleanly).

Edited upstream files:

| File | Change |
|---|---|
| `app/views/welcome/dashboard.html.erb` | Three `render "widgets/slot"` lines. Feature/forms also edits this file (one line, near the top of the left column); the widget lines go elsewhere to avoid a conflict. |
| `config/routes.rb` | `resources :widgets` |
| `config/initializers/features.rb` | The registration above. |
| `app/models/hook.rb` | `"widgets"` in the catalog list. Feature/forms and person-fields edit the same line, so this conflicts on every rebuild until one lands; resolve by rebasing. |
| `db/schema.rb` | The `widgets` table and version line. |

Not done: CodeMirror CSS and JavaScript modes (`config/importmap.rb`, `app/javascript/code_editor.js`). Worth offering upstream on its own later.

## 9. Hooks

- `Widget` includes `CanBeHooked`; add `widgets - create`, `widgets - update`, `widgets - destroy` to `Hook.catalog`. Useful for telling an integration (or an audit channel) that someone changed what everyone sees on the dashboard, especially since widgets can carry JavaScript.
- No domain events. Rendering is read-only and happens on every dashboard load, so a "viewed" event would be noise.

## 10. Tests (Minitest)

- Model: validations (levels, team requirement, `refresh_seconds`, `style_mode`, `placement`).
- Policy: each viewer level for a member, a manager, a non-member and an admin; only admins manage.
- Controller: non-architect admins can't set `dynamic` or `javascript`; `show` refuses someone who can't see the widget; an ERB error renders the fallback, with the message for admins only; a blank body renders blank.
- Dashboard: widgets appear in the right placement and order, hidden ones don't, nothing renders with the feature off.
- Stimulus behavior checked by hand in Chrome on 2026-10-06 against a copy of the dev data: replace mode renders in a shadow root using `var(--bs-primary)`; theme-mode CSS stays inside its widget; the countdown's timer stops when Turbo leaves the dashboard and doesn't stack on return or Back; a 15-second refresh reloads only that card; a manager sees the manager widget, doesn't receive the admin-only one, and the ERB-gated card stays hidden. GatherPack has no JS test runner.

## 11. Examples

### 11.1 Kickoff countdown

Content:

```html
<div class="countdown" data-at="2027-01-09T12:00:00-05:00">
  <span class="days"></span> days <span class="hours"></span> h <span class="mins"></span> m
</div>
```

JavaScript:

```js
const el = root.querySelector(".countdown")
const at = new Date(el.dataset.at)
const tick = () => {
  const s = Math.max(0, (at - Date.now()) / 1000)
  el.querySelector(".days").textContent = Math.floor(s / 86400)
  el.querySelector(".hours").textContent = Math.floor(s % 86400 / 3600)
  el.querySelector(".mins").textContent = Math.floor(s % 3600 / 60)
}
tick()
const timer = setInterval(tick, 1000)
return () => clearInterval(timer)
```

### 11.2 Who's clocked in

The existing Page source (`pages/clocked-in-report.html.erb`), trimmed to the list and counts, with `dynamic` on, viewer `user`, `refresh_seconds` 60, placement `top`. Its access check stays in the ERB and renders nothing for people who shouldn't see it, so the card disappears for them. The page's own reload script and print CSS are dropped.

## 12. Upstream

Upstream naming throughout (`Widget`, `widgets`), no `Hbr` namespace, so the branch can be offered as is. Before any upstream issue or PR, confirm the topic and wording with Corey. Pitch it as a general dashboard extension point.

## 13. Decisions (2026-10-06)

1. **Per-person control.** People can't hide widgets on their own dashboard in v1. Add a dismissed-widgets list later if asked.
2. **Team managers as authors.** No. Only admins author widgets in v1; the dashboard is shared space.
3. **Show an existing Page as a widget.** No. Widgets hold their own content; two sets of permissions on one card would be confusing.
