# Spec: Theming and a modern skin

Status: rev. 2, 2026-11-08. Being built. Pitch: [`07-theming-and-modern-skin.md`](../pitches/07-theming-and-modern-skin.md). Code facts checked against integration `45405a02`. Decisions are in §12.

Rev. 2: the Content Security Policy from the security series, the two intake layouts, and the sidebar slots seam.

Related specs: [`my-gatherpack-spec.md`](my-gatherpack-spec.md) uses the template overrides from §5. [`app-feel-spec.md`](app-feel-spec.md) is independent of this one.

## 1. Goal

Make GatherPack look current, and make the theme page do what it appears to do, without changing controllers, models, permissions or page markup outside a few replaced templates.

The work is finished when:

1. With the flag on, the main screens match the look in the pitch, in light and dark, at desktop and phone widths (§10 lists the screens).
2. With the flag off, every page sends the same CSS and markup as today.
3. An admin can pick a brand color, and that one color reaches buttons, links, focus rings, pagination, the calendar and comboboxes.
4. A signed-out visitor sees a focused sign-in page with the site's own logo and title.

### 1.1 Use cases

| Use case | How |
|---|---|
| A site wants the modern look with no setup | Turn on `feature_modern_skin`; the default palette applies |
| An admin wants to try the look alone first | Preview in their own session (§6.5) |
| A person prefers dark mode, or wants it to follow their device | Light, Dark or Auto, saved on their login (§7) |
| A site has its own brand color and logo | Theme page choices (§8) |
| A site has hand-written CSS variables or custom CSS | Both fields stay and apply last, subject to §8.5 |
| The new look causes a problem | Turn off the flag. Everyone gets today's CSS on their next page |

### 1.2 Non-goals

- Replacing Bootstrap, or a separate front end (the pitch says why).
- Changing what a page shows or how a task flows. That is [`my-gatherpack-spec.md`](my-gatherpack-spec.md).
- Per-team themes, or more than one site theme.
- Restyling emails. Mailer layouts are untouched.

## 2. How it works today

- **Compile-time colors.** `app/assets/stylesheets/application.bootstrap.scss` sets `$primary` to greige and compiles Bootstrap, so `.btn-primary`, `.btn-outline-primary`, `.page-link` and others carry literal color values. Its own `:root` block then sets a few runtime variables (`--bs-primary`, `--bs-body-bg`, `--pair-*`). Setting `--bs-primary` doesn't reach the literal values or `--bs-primary-rgb`.
- **Theme.** `Theme` is a single row (`Theme.instance`) with `css_variables`, `custom_css`, `pwa_theme_color`, `pwa_background_color`, and attached `logo` and `pwa_icon`. `ThemeController` is admin-only.
- **Output.** `layouts/_theme_styles` writes the two text fields into `<style>` tags. The application, devise, kiosk, intake kiosk and intake public layouts render it right after the application stylesheet. **The Doorkeeper layout doesn't render it.**
- **Sign-in.** `layouts/devise.html.erb` hard-codes the "Get Together with GatherPack" `.logoline` and always uses `logo.svg`, even with a site logo. `devise/sessions/new` covers `local_auth`, `local_signup`, rememberable, recoverable and the omniauth partial.
- **Other fixed colors.**
  - `.navtab`, the `table.table th` rule and `.modal-content` in the main stylesheet.
  - 9 color values in `_combobox.scss` and 5 in `_dashboard.scss`.
  - `event_calendar_colors` in `application_helper` hard-codes greige calendar text.
  - `.bg-dark` on the navbar, which is a Bootstrap utility with `!important`.
- **Dark mode.** Bootstrap's dark styles are compiled, but `_themeSwitcher` is never rendered. The app's later `:root` block also beats Bootstrap's `[data-bs-theme=dark]` block, because their specificity is equal.
- **Content Security Policy** is active in report-only mode (`config/initializers/content_security_policy.rb`). `style-src` allows inline styles; `script-src` is `self` plus a per-response nonce. Any inline script the skin adds carries the nonce, so it keeps working if the policy is enforced later. Fonts and images the skin loads must come from `self`.

## 3. Design in three layers

1. **Skin stylesheet** (§6): a separate compiled CSS file that redefines color tokens and restyles existing classes. It's linked only when the skin is active.
2. **Template overrides** (§5): a folder of replacement templates, used only when the skin is active. Everything not in the folder falls through to the original.
3. **Generated palette** (§8): Ruby turns the admin's brand color into the full set of token values, in place of the skin's defaults.

Layers 1 and 2 ship first, with fixed light and dark palettes. Layer 3 waits until the look is approved.

## 4. Branches and flags

| Branch | Based on | Contents | Flag | Upstream |
|---|---|---|---|---|
| `feature/view-overrides` | `upstream/main` | The override seam (§5). No visible change | None; it does nothing until something registers | Candidate |
| `feature/sidebar-slots` | `upstream/main` | A registry of partials and root attributes for the sidebar. No visible change | None; it does nothing until something registers | Candidate |
| `feature/modern-skin` | `feature/view-overrides` + `feature/sidebar-slots` | Skin stylesheet, sign-in override, color mode, preview | `feature_modern_skin`, off | Offer after review |
| `feature/theme-palette` | `feature/modern-skin` | Theme columns, generator, new theme page | `feature_theme_palette`, off | Candidate |

`feature/theme-palette` sits on the skin branch only because both edit `_theme_styles`. The generator doesn't call the skin, and it works on the old look too, so it can be split out if upstream wants the palette alone.

**Upstream files edited**

| File | Branch | Change |
|---|---|---|
| `package.json` | modern-skin | A second Sass target in `build:css:compile` |
| `app/views/layouts/_theme_styles.html.erb` | modern-skin, theme-palette | Skin link, color mode script, palette output |
| `app/views/theme/edit.html.erb` | theme-palette | Renders the new choices when the flag is on |
| `app/controllers/theme_controller.rb` | theme-palette | Permitted fields |
| `config/routes.rb` | modern-skin, theme-palette | Color mode, preview and theme preview routes |

All other work goes in new files and `config/initializers/`. Layouts aren't edited, because `_theme_styles` is already in the head of the layouts that matter. The color mode control and the preview note register in the sidebar slots seam (`feature/sidebar-slots`), so this branch doesn't edit `_sidebar`, and they still appear when My GatherPack replaces the sidebar.

## 5. Template overrides (`feature/view-overrides`)

### 5.1 Seam

```ruby
# config/initializers/modern_skin.rb, inside to_prepare
GatherPack::ViewOverrides.register(
  :modern_skin,
  path: Rails.root.join("app/view_overrides/modern_skin"),
  position: 10,
  active: ->(controller) { ModernSkin.active?(controller) }
)
```

`GatherPack::ViewOverrides` is a small registry in `lib/gatherpack/`. A `before_action` added to `ApplicationController` from `to_prepare` calls `prepend_view_path` for each active override on that request. Higher positions are searched first, so a later feature can replace a template that an earlier one replaced.

Rules:

- A file at `app/view_overrides/<key>/devise/sessions/new.html.erb` replaces `app/views/devise/sessions/new.html.erb`. This covers partials and layouts too.
- Lookup changes for that request only. Mailers don't run the `before_action`, so emails are unaffected.
- The `active` check runs on every request, including signed-out ones, so it can't assume `current_user`.
- No view uses fragment caching today, so template digests aren't a concern.

### 5.2 Drift check

An override doesn't pick up later changes to its original. Feature branches can't check this reliably, because a branch based on upstream sees a different original than integration does. So the check runs on integration:

- `fork/view-overrides.lock` on `hbr/platform` lists each override with the Git blob hash of its original, as of the last review.
- `bin/fork-override-check`, run by `bin/fork-rebuild` after the merge, compares them and prints each changed original with its diff. A change is a warning to review, not a failure.
- After a review, `bin/fork-override-check --ref origin/hbr/integration --accept <path>`, run in `platform/`, updates the lock.

This is built and on `hbr/platform` (`fork/STRATEGY.md`, "Replaced templates"). Each new override shows as "not reviewed yet" until it's accepted.

## 6. Skin stylesheet (`feature/modern-skin`)

### 6.1 Build

Add `./app/assets/stylesheets/skin/skin.scss:./app/assets/builds/skin.css` to `build:css:compile`. The prefix step runs on the new file too. The application stylesheet doesn't change, which is what makes the flag a full rollback. The skin imports no Bootstrap source, so it stays small. The trial CSS was about 5 KB and the complete file should stay under 40 KB.

### 6.2 Where it loads

`_theme_styles` adds, when the skin is active:

```erb
<%= stylesheet_link_tag "skin", "data-turbo-track": "reload" %>
```

The partial renders after the application stylesheet, so the skin wins on equal specificity. Admin CSS comes after it. Because the link is tracked, a Turbo visit does a full reload if the flag changes, so nobody is stuck with mixed CSS.

### 6.3 Tokens

Start from `notes/reskin-proof/skin-proof.css` and `skin-proof-dark.css`, which are local to the workspace, for layout. The defaults are GatherPack's own greige, made readable. A team's colors come only from site configuration, never from these tokens. All colors become `--gp-*` tokens, and Bootstrap, FullCalendar and app variables read from them.

| Token | Light | Dark | Used for |
|---|---|---|---|
| `--gp-brand` | `#6d6753`, GatherPack's `$greige-dark` (white text reaches 4.5:1) | Lightened greige that passes on `--gp-surface` | Actions, links, focus |
| `--gp-brand-rgb` | matching triplet | matching triplet | `--bs-primary-rgb`, `--bs-link-color-rgb` |
| `--gp-brand-hover`, `--gp-brand-soft` | derived | derived | Hover, tints |
| `--gp-on-brand` | `#fff` | chosen for contrast | Text on brand color |
| `--gp-success`, `--gp-success-rgb`, `--gp-success-soft` | Green that reaches 4.5:1 | Lightened green | Status only (Clocked in, Signed up), so a neutral brand doesn't lose the meaning |
| `--gp-page` | `#ebe6d8`, the product's greige page lightened so links on it reach 4.5:1 | Warm dark greige | Page background |
| `--gp-surface` | `#fffdf6`, the product's `$greige-lightest` | Warm dark greige, one step up | Cards, navbar, sidebar |
| `--gp-border`, `--gp-text`, `--gp-muted` | Greige tones (`$greige-light`, `$greige-darkest`) that reach 4.5:1 for text | Greige tones that reach 4.5:1 for text | Lines and text |
| `--gp-radius` | `10px` | same | Corners |
| `--gp-font` | Inter, then system fonts | same | All text except code |

Light tokens go in `:root`, so they beat the application stylesheet's `:root` by source order. Dark tokens go in `:root[data-bs-theme=dark]`.

Inter ships as one local variable `woff2` in the skin branch, with `font-display: swap`. Nothing new loads from a CDN. The existing Google Fonts link stays, but browsers don't download its fonts when nothing uses them.

### 6.4 Rules for the CSS

- Target class names the views already emit (`card`, `btn-primary`, `table`). Add no classes to existing templates.
- **No blanket `!important`.** The trial used it as a shortcut. It's allowed only to beat a Bootstrap utility that has it, with a comment. Prefer redefining the variable the utility reads. For example, `header.navbar { --bs-dark-rgb: ... }` handles `.bg-dark`.
- The same rules serve both palettes. A rule with a literal color fails review.
- **Print stays light.** Inside `@media print`, reset the tokens to light values for both modes. Report print styles (the `report_print_css` Variable) must come out unchanged.
- **Phone width from the start.** Use the same breakpoints as the current layout. The skin hides breadcrumbs on phones. Other phone work is in My GatherPack.

### 6.5 Who gets the skin

```ruby
ModernSkin.active?(controller) =
  GatherPack::Features.enabled?(:modern_skin) || controller.session[:skin_preview] == true
```

Preview: a "Preview the new look" button on the theme page (admin only) sets `session[:skin_preview]`, and "Stop previewing" clears it. Preview doesn't touch anyone else's view and ends with the session. While it's on, a small note in the sidebar says so, with the Stop button. A signed-out preview of the sign-in page isn't offered; check that page on the staging copy with the flag on.

### 6.6 Coverage to handle explicitly

| Item | Light | Dark |
|---|---|---|
| Buttons, outline buttons, pagination, `.text-bg-*`, active list and dropdown items | Tokens | Tokens |
| `btn-success` (Search and others) | Same as primary, so only one green is on screen | Same |
| FullCalendar | `--fc-*` from tokens | Same |
| `event_calendar_colors` greige text | `ApplicationHelper.prepend` a version using `contrasting_color`'s black and white defaults, when the skin is active | Same |
| Combobox | Redefine its 9 values | Same |
| Trix, CodeMirror (`--app-code-*`) | Check | Must be readable |
| Tables, modals, `.navtab`, alerts, flash | Rules from the proof | Tokens |
| Team and event type colors | Keep; they use `contrasting_color` | Check against dark surfaces |
| Site logo | As uploaded | May disappear on dark; see §8.2 |
| Stored Pages and widgets with inline colors | Unchanged | Audit. Fallback: give their container a scoped set of light tokens, so they show as a light panel on a dark page |
| Kiosk | Skin applies; check `_kiosk.scss` | Always light (§7.3) |

## 7. Color mode (`feature/modern-skin`)

### 7.1 Data

One reversible migration: `users.color_mode`, a nullable string (`light`, `dark`; null means Auto). It's saved on the login so it follows the person across devices, and so a shared laptop doesn't hand one person's choice to the next.

### 7.2 Applying it

`_theme_styles` adds a small inline script in the head, so the page never flashes the wrong mode:

```erb
<%= javascript_tag nonce: true do %>
  (function () {
    var saved = <%= raw json_escape(color_mode_for_page.to_json) %>;
    var mode = saved || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    document.documentElement.setAttribute("data-bs-theme", mode);
  })();
<% end %>
```

Written only when the skin is active. `color_mode_for_page` returns `"light"` on the kiosk, otherwise the real user's choice (`true_user`, so impersonating doesn't change an admin's mode), or null. `<html>` survives Turbo visits, so the attribute persists between pages. A Stimulus controller follows device changes while the mode is Auto.

### 7.3 Rules

- **Signed out:** Auto.
- **Kiosk and intake kiosk:** always light. They're shared devices, and their mode shouldn't change with the time of day.
- **Intake public pages:** Auto, the same as any signed-out page.
- **Print:** always light (§6.4).

### 7.4 Control

Three small buttons, Light, Dark and Auto, at the bottom of the sidebar. The partial is `layouts/_color_mode`, registered in the sidebar slots, and renders nothing when the skin is off. A click applies the mode at once and saves it with `PATCH /color_mode`.

`ColorModesController < InternalController` updates only `current_user`, or `true_user` when impersonating. It uses `update_columns`, because this is a display preference and shouldn't fire `users - update` hooks or add audit rows.

## 8. Generated palette (`feature/theme-palette`)

An admin picks a few base colors, and the app works out every other color in light and dark, keeping text readable. Nobody should need to hand-write color variables to get a working site. The feature applies while the skin is on; with the skin off, the theme page stays as it is today.

### 8.1 Data

One reversible migration on `themes`. All are `#rrggbb` or null, validated by `Theme.include(ThemePalette::Choices)`, so these fields can't inject CSS.

| Column | Label | Null means |
|---|---|---|
| `brand_color` | Brand | The skin's default greige |
| `background_color` | Page background | The skin's default |
| `surface_color` | Cards and menus | Worked out from the page background |
| `text_color` | Text | Whichever reads best on the page background |

Font, corner style and a dark-mode logo are not part of this branch.

### 8.2 Generator

`ThemePalette::Generator.new(theme).css` is a plain Ruby object with no database or view access. It returns the `--gp-*` tokens for light and dark, and repeats the light set inside `@media print`.

- **Light** uses the picks directly. Cards, raised areas, borders, input borders, muted text, hover and soft tints derive from them.
- **Dark** derives from the same hues: a dark page and surface tinted like the page background, light text, and the brand adjusted to work there. There are no separate dark pickers in this version.
- **Fills and text are separate.** `--gp-brand` is a fill and `--gp-on-brand` is black or white, whichever reads better. `--gp-accent` is the brand shifted until it reaches 4.5:1 on the page and on cards, for links and outlined buttons.
- **Derived colors are always readable.** Muted text and accents move until they pass 4.5:1, and input borders 3:1. Status colors stay status colors, adjusted if they'd be unreadable on the chosen surfaces.
- **A color the admin picked is never changed.** `Generator#warnings` names any picked pair that can't reach 4.5:1. Saving is not blocked.

`_theme_styles` writes the result after the skin link and before the Advanced CSS.

### 8.3 Theme page

With `feature_theme_palette` on, `theme/edit` shows a **Colors** section first: one color picker with a hex field per base color, and an "Automatic" choice for each that may be empty. "Reset to defaults" clears them all.

**Preview.** Two iframes, light and dark, load `GET /theme/preview` with the picks as parameters. That admin-only page renders real components (buttons, links, a card, a table, a form, the text editor, the code editor, status badges) with sample text and saves nothing. A Stimulus controller refreshes them as colors change.

**Warnings** appear above Save and don't block it.

The PWA pickers are relabeled "Installed app colors", with a note that they only affect the app's status bar and splash screen. CSS Variables and Custom CSS move into a closed Advanced section with their values kept.

### 8.4 Existing themes

Old variables and CSS still apply after the generated palette, so they can undo it. When `css_variables` isn't blank, the Colors section says so and offers **Use these as my starting colors**: it maps `--bs-primary` to Brand, `--bs-body-bg` to Page background, `--bs-card-bg` to Cards and `--bs-body-color` to Text, leaving out a text color that wouldn't be readable, then clears `css_variables`. Custom CSS is never cleared automatically, but a rule that sets a color on the editors gets a warning naming it. Nothing changes until an admin presses a button.

### 8.5 Editors

The code editor (CodeMirror) and the rich text editor (Trix) take their background, text, gutter, toolbar, selection and syntax colors from the tokens, and stay readable in both modes and with any palette.

## 9. Sign-in page

Overrides in `app/view_overrides/modern_skin/`:

- `layouts/devise.html.erb`: same head content, including the manifest link. Drops `.logoline` and the slogan, and uses a centered column about 400 px wide. Shows `Theme.instance.logo` and `Settings[:title]`, or `logo.svg` with the title when no logo is attached. A small muted "powered by GatherPack" link stays at the bottom.
- `devise/sessions/new.html.erb`: one card headed "Sign in", then fields and a full-width button. Keeps every existing branch: `local_auth`, `local_signup`, rememberable, recoverable, the omniauth partial, and `data: { turbo: false }` on the form.

The other Devise pages get the new layout without their own overrides. The Doorkeeper consent page has a separate layout and doesn't run `ApplicationController`'s filters, so it's a later, separate override.

## 10. Tests

- **Seam:** an override replaces a template only while its `active` check is true; a template with no override falls through; two overrides resolve by position; a mailer is unaffected.
- **Rollback:** with the flag off, `application.html`, the devise layout and the kiosk layout have no `skin` link, no color mode script and no `data-bs-theme` attribute.
- **Sign-in:** one test per branch (`local_auth` off, `local_signup` on, an omniauth provider, a site logo, no logo).
- **Color mode:** saving works; another user's mode can't be changed; no audit row and no hook fired; impersonation uses the real user; the kiosk is always light.
- **Generator:** known inputs give expected outputs; each derived pair passes contrast across a matrix of picks, and each picked pair passes or appears in `warnings`; invalid hex is rejected by the model.
- **Coverage check:** a test reads the compiled `application.css`, finds each rule using the old literal primary (32 uses, plus 13 RGB triplets), and fails if the skin doesn't redefine that component. This catches a new Bootstrap component after an upstream upgrade.
- **Visual pass, by script.** Playwright in the installed Chrome, against the demo site with the flag on, takes screenshots in light and dark at 1440 px and 390 px. Screens:
  - Sign-in, password reset and dashboard.
  - People list and a person's profile.
  - Teams, a team, an event with check-ins, and the calendar (each view).
  - A form being filled in, form results, a sign-up sheet and its roster.
  - Time clock, the kiosk, a ledger with entries, and the ledger payment page.
  - A modal, a Page, a widget, a printed report, and the theme page.

  Add an automated contrast scan (axe) of the same screens. The phone and dark results are reviewed by a person.

## 11. Hooks, sample data and phases

**Hooks.** No new models, so no new catalog entries. `Theme` doesn't include `CanBeHooked` today, and theme changes aren't an event anyone has asked to automate. `users.color_mode` deliberately skips the existing `users - update` hook (§7.4).

**MCP.** Themes stay out of MCP, as [`mcp-expansion-spec.md`](mcp-expansion-spec.md) §3 says.

**Sample data.** `fork/sample_data/features/modern-skin.rb` leaves the flag off and adds nothing else. `theme-palette.rb` sets a Northwind brand color. `view-overrides` needs only an empty file.

**Phases.** Each can ship alone, and each ends with a review.

1. **The look.** `feature/view-overrides` and `feature/modern-skin`, with fixed palettes, color mode, sign-in and preview. Review on the staging copy in both modes and both widths (§10). Its review decides whether the look stands before anyone builds phase 2.
2. **Coverage fixes.** Whatever the visual pass finds, including the audit of stored Pages and widgets.
3. **The choices.** `feature/theme-palette`.

## 12. Decisions

1. **Keep Bootstrap class names as the contract.** They're how 420 templates describe themselves. Tests also select on them.
2. **Separate stylesheet, not changes to the existing one.** It's what makes the flag a full rollback, and it avoids conflicts in the most-edited CSS file.
3. **Color mode is saved on the login, not per device.** It's the person's choice. A device-level cookie would carry over on shared laptops, and Auto already follows each device.
4. **Colors are computed in Ruby, once.** The preview asks the server, so JavaScript can't disagree with the saved result.
5. **Contrast warnings don't block saving.** The warning sits above Save, with no alert at the top of the page. An admin may have reasons, and the advanced fields can break contrast anyway.
6. **Old CSS variables aren't migrated.** There's no reliable automatic mapping from free text to choices. Review them when switching a site over.
7. **Overrides are checked on integration, not in unit tests.** Only integration has the original the override actually replaces.
8. **Stored Pages and widgets in dark mode.** If the audit finds too many to fix, they show as a light panel on a dark page.
9. **"Powered by GatherPack" stays on the sign-in page,** smaller and muted.
10. **Fonts on the theme page:** System, Inter and one serif. Each extra font adds a local file.
