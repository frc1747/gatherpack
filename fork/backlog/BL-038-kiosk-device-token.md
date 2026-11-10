# BL-038: Let a dedicated kiosk computer stay on the time clock without a user login

| | |
|---|---|
| Kind | upstream feature |
| Priority | medium |
| Status | new |
| Added | 2026-11-09 |
| Upstream commit checked | `eeaa691a` (`upstream/main`) |
| Planned branch | `feature/kiosk-devices` (none yet) |
| Upstream issue / PR | none |

## Summary

The time clock kiosk (`/time_kiosk`) only works while some user is signed in. A dedicated kiosk computer has to be signed in to a real account, and it falls back to the login page once that sign-in is lost. Add kiosk devices: an admin pairs a computer once, and from then on that browser can use the time clock, and only the time clock, with no user session.

## How it works today

- `TimeKioskController` inherits `ApplicationController` (`app/controllers/time_kiosk_controller.rb:1`), whose `before_action :check_for_user` (`app/controllers/application_controller.rb:8`, `:32`) sends anyone not signed in to the login page.
- Nothing the kiosk does depends on *which* user is signed in. Punches come from the scanned token's person (`app/models/time_kiosk.rb`), and mass clock-out checks the scanned person's own permissions. The only uses of `current_user` are the header name and avatar in `app/views/layouts/kiosk.html.erb:46-61`.
- Staying signed in depends on Devise "Remember me". That lasts 2 weeks from sign-in and doesn't extend with use (`config/initializers/devise.rb:167`, `:173`), and with `expire_all_remember_me_on_sign_out = true` (`:170`) one sign-out of that account anywhere ends it. The usual workaround is Chrome's "Continue where you left off", which keeps the session cookie through reboots, but clearing browser data or switching profiles loses it.
- Because a full user is signed in, the brand link in the kiosk header (`app/views/layouts/kiosk.html.erb:34`, `href="/"`) opens the whole app as that account for anyone standing at the kiosk.

## Design

**Model.** `KioskDevice` (`has_neat_id :kdv`, paper trail):
- `name`: shown in the kiosk header, e.g. "Shop door".
- `secret_digest`: the secret is stored only as a SHA-256 digest.
- `pairing_code_digest` and `pairing_expires_at`.
- `last_seen_at`, `revoked_at`, `created_by` (user).

The migration is new and reversible.

**Managing devices.** Under Time Clock there's a "Kiosk devices" list, for admins only (Pundit policy, `admin?`). From it an admin can:
- **Add a device.** This shows a one-time pairing link, `/time_kiosk/pair/<code>`, valid for 1 hour and shown only once.
- **Revoke a device.** It stops working on its next request.
- **Re-pair a device.** This issues a new code and invalidates the old secret.

The list shows each device's last-seen time.

**Pairing.** Opening the link on the kiosk computer:
1. Checks the code.
2. Generates the device secret.
3. Sets a permanent, signed, `httponly`, `secure`, `SameSite=Lax` cookie `kiosk_device` that holds the device id and secret.
4. Clears the pairing code.
5. Redirects to `/time_kiosk`.

Pairing doesn't need a signed-in user, because the code is the credential.

**Authentication.** In `TimeKioskController`, skip `check_for_user` when the `kiosk_device` cookie matches a device that isn't revoked (compare digests with `ActiveSupport::SecurityUtils.secure_compare`), and touch `last_seen_at` at most once an hour. Put this in a concern (`KioskDeviceAuthentication`) so the edit to the controller is one `include`. No user session is ever created, so the device can reach the kiosk routes and nothing else. The brand link and every other page lead to the login page. A signed-in user still uses the kiosk exactly as today.

**Kiosk layout.** When there's no `current_user`, the header shows the device name instead of a person, and the brand link is removed.

**Flag.** `Settings` key `kiosk_devices`, default off and registered through `Settings.register`. When it's off, the pairing route returns 404 and device cookies are ignored. It sits under the `:time_tracking` feature, like the kiosk routes (`config/routes.rb:94`).

**Scope.** A paired device gets exactly what the kiosk page gives a signed-in user today, no more. This item doesn't change what the kiosk actions themselves allow.

## Tests

- Model: secret and code digests, expiry, revoke, re-pair invalidating the old secret.
- Controller/integration:
  - With a paired cookie, `/time_kiosk` renders and a punch in/out works with no user.
  - A revoked device, a tampered cookie, or the flag off redirects to login.
  - An expired or reused pairing code is refused.
  - With a device cookie alone, a non-kiosk page (e.g. `/people`) still redirects to login.
- Policy: only admins can list, add, revoke or re-pair devices.
- System: the kiosk header shows the device name and no brand link when no user is signed in.

## Fork strategy notes

- This is an upstream feature (upstream ships the kiosk), so it's built on `feature/kiosk-devices` from `upstream/main` to upstream's standards.
- Upstream files touched: `time_kiosk_controller.rb` (one include), `layouts/kiosk.html.erb` (header branch), `config/routes.rb` (pair route and devices resource inside the `:time_tracking` block). List them in `FORK.md`.
- It touches the same controller as BL-012 and BL-027, so rebase onto whichever of those is still carried at sync time.

## Draft upstream text

> **Kiosk devices: keep a dedicated time clock computer running without a user login**
>
> Today the time kiosk needs a signed-in user, so a kiosk computer uses someone's account, drops to the login page when the session is lost, and exposes the full app through the header link. This adds kiosk devices: an admin pairs a computer once with a one-time link, and that browser can then use the time clock (and only the time clock) until the device is revoked. Off by default behind the `kiosk_devices` setting.
