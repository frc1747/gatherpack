# BL-040: Read the kiosk's card scanner as a serial device instead of a keyboard

| | |
|---|---|
| Kind | fork-only |
| Priority | low |
| Status | waiting |
| Added | 2026-11-10 |
| Commit checked | `feature/kiosk-auto-clock-in` @ `87632f17` (`upstream/main` @ `eeaa691a`) |
| Planned branch | `feature/kiosk-serial-scanner` (from `feature/kiosk-auto-clock-in`) |
| Upstream issue / PR | none |

## Summary

The kiosk's barcode scanner is set up as a keyboard. It types each scan into whatever has focus. On the touch-screen kiosk, a tap on the page can take focus away from the Token box, and the next scan is lost. If the scanner is set to its USB serial ("virtual COM" / USB CDC) mode, Chrome can read it directly through the Web Serial API. Scans would reach the kiosk page no matter what has focus.

**Waiting on:** a trial of the "Kiosk: Keep the Token Box Ready" setting (`time_kiosk_keep_focus`) on the real kiosk after the next release. Pick this up only if scans still go missing with that setting on.

## How it works today

- Upstream: the Welcome screen (`app/views/time_kiosk/_welcome.html.erb`) has a Token box (`input[name='time_kiosk[token_value]']`). The scanner types the code and an Enter, which submits the form to `TimeKioskController#find_token`.
- Fork, `feature/kiosk-auto-clock-in` @ `87632f17`: `app/javascript/controllers/kiosk_focus_controller.js` runs when `time_kiosk_keep_focus` is on (default off). It sends taps on plain page area back to the Token box, puts focus back when it drifts to the page, and leaves focus alone while a modal (the Manager window) is open. This is the keyboard-mode fix being tried first.
- Keyboard mode still has limits that the focus fix can't remove. A scan during an open modal, or while focus is in another field, goes to the wrong place. Typing on the touch keyboard looks the same as a scan.

## Design

- New setting in `TimeKiosk::Config`: "Kiosk: Read the Scanner as a Serial Device" (`time_kiosk_serial_scanner`, default off). Off leaves the kiosk exactly as it is now.
- New Stimulus controller `kiosk_serial_controller.js` on the kiosk page when the setting is on:
  - On connect, `navigator.serial.getPorts()`. If a port was granted before, open it (try 9600 baud by default; make the baud rate a setting if the scanner needs another) and read lines.
  - If no port is granted, show a small "Connect scanner" button. Chrome only shows its port picker after a tap, so this has to be a button (`navigator.serial.requestPort()`). Once granted, Chrome remembers the port for this site.
  - Each complete line (ended by CR or LF, trimmed) fills the Token box and submits the same form. The server side doesn't change.
  - Listen for `navigator.serial` `connect` / `disconnect` events. Reopen the port when the scanner is plugged back in. Show a quiet "Scanner disconnected" note while it's gone.
  - While the Manager window is open, ignore scans or queue one, matching what keyboard mode does today.
  - If `navigator.serial` is missing (Firefox, Safari), do nothing. Keyboard input keeps working.
- Keyboard input stays as the fallback, so a scanner left in keyboard mode still works.
- Kiosk machine setup (document in the kiosk spec, not in code):
  - Put the scanner in USB CDC / virtual COM mode, set it to add CR after each code, and turn off its keyboard mode.
  - Chrome or Edge only. The page must be HTTPS (production is).
  - On a Linux kiosk, the browser's user needs access to `/dev/ttyACM*` (usually the `dialout` group).
  - To skip the one-time picker on a managed Chrome, the enterprise policy `SerialAllowUsbDevicesForUrls` (scanner's USB vendor/product id) or `SerialAllowAllPortsForUrls` can grant the port to the kiosk URL.
- Alternative not chosen: WebHID with the scanner in "HID POS" mode. Fewer scanners support it, and the code is harder to write.
- Content Security Policy: Web Serial needs no CSP change. Check the `permissions_policy` initializer on `feature/security-series` doesn't block `serial` for the page itself.

## Tests

- Stimulus logic can't open a real port in system tests. Put line splitting and submit in a small module with a fake reader and test that (or a system test that stubs `navigator.serial` with a fake port that emits `1747xxxxxxxx\r`).
- Setting off: the kiosk page has no serial controller.
- Setting on, no `navigator.serial`: the page still submits on keyboard input.
- Check by hand on the real kiosk with the scanner in serial mode: scan with focus on the page, with the touch keyboard open, after unplugging and plugging the scanner back in, and after a Chrome restart (no picker should show the second time).

## Fork strategy notes

- Branch from `feature/kiosk-auto-clock-in`, where `TimeKiosk::Config` and the other kiosk Stimulus controllers live. New files plus one render or `data-controller` line in `app/views/time_kiosk/_kiosk.html.erb` (already listed in that feature's upstream files).
- `feature/security-series` merges `feature/kiosk-auto-clock-in`. Check the `permissions_policy` note above on the combined build.
- Fork-only for now. Upstream's kiosk could use it too, but it rests on the fork's kiosk settings. Ask Corey before pitching it.
- Related: BL-038 (kiosk devices without a user login) and BL-039 (no Sign out on the kiosk). Both are about keeping a dedicated kiosk ready without anyone at it.
