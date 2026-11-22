# BL-080: No "Signed out successfully." after signing out

| | |
|---|---|
| Kind | fork-only (bug) |
| Priority | low |
| Status | open |
| Added | 2026-11-22 |
| Commit checked | `hbr/integration` @ `e3cc619f5` (`v0.0.0-hbr.52`) |
| Planned branches | `feature/quiet-root-signin` |
| Upstream issue / PR | none |

## Summary

After **Sign Out**, the sign-in page shows no "Signed out successfully." message, so people can't tell it worked.

## Evidence

- Devise sets the `signed_out` flash and redirects to `/` (`after_sign_out_path_for` only changes the path for an OAuth return: `app/controllers/concerns/oauth_authorization_return.rb:35`).
- `/` signed out redirects again to the sign-in page: `config/initializers/quiet_root_signin.rb:5-9` (`4adc5e6df`). That second request uses up the flash, so the sign-in page has none. Upstream's `WelcomeController#index` (`else` branch) redirects the same way.
- Flash rendering didn't change (`app/views/layouts/application.html.erb:52-62`).
- The help site also saw no "Your password has been changed successfully" after a password change. A password change from a person's page goes through `UsersController#update` (`app/controllers/users_controller.rb:29-39`), which says "User information was successfully updated." and never that Devise message, which only the reset-password flow sets. Nothing to fix there unless a reset-password run shows it missing; check that path when fixing this.

## Fix

In `quiet_root_signin.rb`, call `flash.keep` before redirecting to the sign-in page. Leave upstream's `WelcomeController` alone.

## Tests

- Integration: `delete destroy_user_session_path`, follow both redirects, and the sign-in page shows "Signed out successfully."
- Reset-password flow: after setting a new password, the next page shows Devise's "Your password has been changed successfully" message.

## Fork notes

Fork-only. No upstream files.
