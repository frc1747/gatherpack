# BL-076: Print style as a site setting

Printed pages use the site's screen styles: dark backgrounds, sidebars, buttons and cramped tables on paper. HBR fixes this only for its report Pages, by hand: each Page source starts with `<style><%= raw Variable.find_by(name: "report_print_css")&.raw_value.to_s %></style>`, reading a Variable an admin edits. Fork tables printed with Print (form results, checklist reports, rosters) get none of it.

## Evidence

- `report_print_css` is referenced by no app code (only `test/integration/modern_skin_test.rb:100` and HBR's Page sources); its source is kept outside the repo.
- Upstream's `app/assets/stylesheets/_print.scss` has only `.no-print` and a few `main` rules.
- The theme screen is upstream (`ThemeController`, singleton `Theme`); its styles are emitted by `layouts/_theme_styles.html.erb`, which `feature/modern-skin` and `feature/theme-palette` already touch.

## Fix

New branch `feature/print-style`, flag-free (a blank setting changes nothing; the shipped default only applies in `@media print`, and a site can clear it).

- **Setting** `print_css` (text, `Settings.register`), label **Print style**, help: "Styles used when any page is printed. Leave blank to print pages as they look on screen." Default: a bundled stylesheet `app/assets/stylesheets/print_default.css` covering US Letter and A4 margins, hidden navigation, sidebar, buttons, alerts and `.no-print`, black text on white, table headers repeated on each page, badge colours kept, page numbers in the `@page` margin box, and `.print-landscape` support (`main:has(.print-landscape) { page: landscape }`).
- **Where it's set:** a **Print style** card on the Theme edit page, below the theme form (one `render` line in `theme/edit.html.erb`), with its own textarea, Cancel and Save, posting to a fork controller (`PrintStylesController#update`, admin only). "Reset to the default" link fills the textarea with the bundled stylesheet.
- **Where it applies:** one `render` line in `layouts/_theme_styles.html.erb` emitting `<style media="print">` with the setting, on every page. Report Pages no longer need their own include.
- Existing sites: the setting starts at the bundled default. HBR's data step at release copies the `report_print_css` Variable's text into the setting and removes the per-Page include lines (hbr-pages skill).

## Tests

Controller test (admin saves, non-admin refused, blank allowed); layout test that the `<style media="print">` appears with the saved text and not when blank; a system print check is not needed.

## Fork notes

Upstream files: `theme/edit.html.erb`, `layouts/_theme_styles.html.erb` (one line each). Joins the manifest after `feature/theme-palette`'s dependents: at the end. gphelp: a short "Printing" note on the Theme page.
