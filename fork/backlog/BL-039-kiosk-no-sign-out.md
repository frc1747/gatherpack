# BL-039: Take the Sign out button off the kiosk account's kiosk header

| | |
|---|---|
| Kind | fork change |
| Priority | medium |
| Status | new |
| Added | 2026-11-09 |
| Commit checked | `feature/security-series` @ `704bf4c2` |
| Planned branch | `feature/security-series` (fix on the branch itself) |
| Upstream issue / PR | none |

## Summary

A kiosk account's time kiosk shows a "Sign out" button in its header. Anyone at the kiosk can tap it, and then the kiosk sits on the login page until a mentor comes and signs it in again. A kiosk account shouldn't get a Sign out button.

## How it works today

- The button was added by the security series (`f9545893`, "Keep kiosk accounts to the time kiosk, and end their sessions overnight"). It's in `app/views/layouts/kiosk.html.erb:46-48` on `feature/security-series`, shown only when `kiosk_account?` is true:
  ```erb
  <% if kiosk_account? %>
    <%= button_to "Sign out", destroy_user_session_path, method: :delete, data: { turbo: false }, class: "btn btn-outline-light btn-sm" %>
  <% end %>
  ```
  The comment above it (`:41`) says it's there because a kiosk account can't reach the sidebar's Sign Out.
- Upstream's kiosk layout has no sign-out control at all. This is a fork-only addition.
- `kiosk_account?` (`KioskConfinement`, `User#kiosk_account?`) is false for admins, so only non-admin kiosk accounts, the ones on shared devices, get the button.
- `test/integration/kiosk_session_test.rb:103` ("a kiosk account can sign out from the kiosk") asserts the button's form is on the page.

## Design

- Remove the `kiosk_account?` Sign out block from `layouts/kiosk.html.erb`. Keep "Stop Impersonating" in the same `d-flex` wrapper. Update the comment to say only the impersonation exit is there.
- Leave the sessions route and `KioskConfinement#signing_in_or_out?` alone. Sign-out is `DELETE` only (`config.sign_out_via = :delete`), so without the button nobody at the kiosk can reach it.
- This is the stopgap. A kiosk account still ends at its 12-hour idle timeout (`User::KIOSK_TIMEOUT`) or a Chrome restart that loses the session cookie. The goal is a kiosk that never signs out, and that's BL-038: a paired device has no user session, so nothing times out and there's no Sign out to tap.
- Regular users on the kiosk keep their usual way out (the brand link to the app, then the sidebar), unchanged.
- No flag: it removes a fork-only button and restores upstream's layout for this case.

## Tests

- Replace `kiosk_session_test.rb:103` with: a kiosk account's kiosk page has no sign-out form (`assert_select "form[action=?]", destroy_user_session_path, count: 0`).
- An admin impersonating a kiosk account still sees "Stop Impersonating".

## Fork strategy notes

- The fix goes on `feature/security-series`, where the button lives. The fit branches that merge the security series (`feature/turbo-frame-links-fit`, `feature/local-assets-fit`) pick it up at the next rebuild. `feature/local-assets` also edits `layouts/kiosk.html.erb` (head lines only), so check that merge at sync.
- BL-038 (kiosk devices) is the lasting fix. Once dedicated kiosks are paired devices, kiosk accounts only matter for kiosks not yet paired.
