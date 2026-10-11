# Time kiosk improvements

## Summary

Two changes to the time kiosk, applied in order. Phase 1 is a security
fix: kiosk actions are tied to a card number lookup instead of ids the
browser sends. Phase 2 adds optional settings for one-scan clock-in,
clearing the screen automatically, and limiting who can open the kiosk.
Every Phase 2 default leaves the kiosk as it behaves today.

## Phase 1: tie kiosk actions to a card lookup

### Problem

Entering a card number only looks the person up and shows their screen.
The buttons on that screen are plain URLs carrying ids, and the server
performs whatever those URLs say without checking that a card was
entered or that the ids belong to the person shown:

- Clock In sends a person id and a period id.
- Clock Out sends only a punch id, with no person at all.
- The manager's mass clock-out sends only the manager's person id.

So a hand-built or edited URL (parameter tampering) acts on any person
or punch without a card number. Kiosk punches also skip the normal punch
permission rules, so such a request can clock someone into a period they
can't use, stack duplicate open punches, rewrite the end time of a punch
that is already finished, or clock out every open punch in a manager's
periods. These actions also accept GET, so a link opened in any
signed-in browser triggers them (cross-site request forgery).

Each request names a `tool`: the step to run (`find_token`, `punch_in`,
`punch_out`, `punch_out_period`, `punch_out_all`), after which the
controller sets it to the screen to show (`welcome`, `found_person`,
`not_found`) and renders the partial of that name. The browser's value
reaches `render` unchecked, so an unknown name, or scanning a Hook's
token, causes a 500 error. Card lookups have no rate limit.

### What it does

- The lookup issues a signed reference to the person, valid for 5
  minutes, and the screen's buttons carry it instead of raw ids. Only the
  server can create one, so an edited URL fails. Every punch action
  requires a valid reference and acts only for that person: their own
  open punches, and periods they can use.
- A finished punch can't be changed, and a person already clocked in to a
  period can't be clocked in to it again.
- Clocking in and out requires POST.
- Only the five step names are accepted, and only the three screens are
  rendered; anything else shows Welcome.
- A Hook's token shows "not found" instead of an error.
- Card lookups are limited to 60 a minute per signed-in user.

Normal kiosk use looks the same.

Out of scope: the card number is the credential. Anyone who has a
person's number can still act for them at the kiosk, as with any barcode
or RFID card. Limiting which accounts can open the kiosk is Phase 2's
access setting.

## Phase 2: faster clock-in

### Problem

Clocking in takes a scan and then a tap, even when only one period
applies. The scanned person's screen stays up for the next person to see.

The kiosk also needs a signed-in session on a shared screen. Whoever
sets it up, often an admin or manager, leaves their own session there,
and the header logo leads from the kiosk into the full app as that
account. Any account can open the kiosk, so nothing steers setup toward
a dedicated kiosk account.

### What it does

Three settings in the Time Clock group:

- **Allow unassigned punches** (default on). When off, and exactly one
  period applies to the person, a scan clocks them in immediately and
  shows a confirmation banner. With two or more periods, the person
  chooses as today. A second scan never clocks out, so a double scan
  can't end a shift. Banners cover already clocked in, already clocked
  out today, and a missed clock-out from an earlier day.
- **Return to Welcome after N seconds** (default 0, off). The person's
  screen clears itself. The countdown pauses while the Manager window is
  open, up to a limit.
- **Who can open the kiosk** (default: anyone signed in). When a team is
  chosen, only its direct members and admins can open `/time_kiosk`. A
  team holding only a plain kiosk account (no admin or manager role) lets
  the shared screen run under that account instead of a person's.

Also: the button reads "Clock In" when unassigned punches are off, and an
unknown card shows "Card not recognized" on the Welcome screen.

## How it's built

- **Phase 1** edits only kiosk files: `time_kiosk_controller.rb`,
  `time_kiosk.rb`, and two kiosk partials (button URLs and an allowlist).
  Fills in the empty kiosk controller test. Deletes one unused partial.
- **Phase 2** adds three lines to `lib/settings.rb` and makes small edits
  to the kiosk controller and two partials. The rest is new files: the
  auto clock-in logic, a team dropdown input for the Settings page, the
  return timer, and tests.
- No migrations or feature flag; the settings are the switch.

## Open choices

- Whether to keep "Start Unassigned". It currently does nothing; that is
  a separate bug.
- Setting names.
- "Who can open the kiosk" is a stopgap: the screen still holds a
  signed-in session. A fuller answer is registering kiosks as devices
  that need no account (spec §8, not built).

Other kiosk and settings bugs found along the way are listed in spec §10.
