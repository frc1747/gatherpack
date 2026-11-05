# App feel

## Summary

Make GatherPack feel like an app: pages that change smoothly, saves that
don't lose your place, an icon on the home screen, and reminders that
reach a phone. This stays on the Hotwire stack GatherPack already uses
(Turbo and Stimulus), which is built for this and is barely used for it
today. No screens are rewritten, and no separate front end is needed.

## Problem

Pages can flicker or jump as they change, which makes a site feel old even
when it is fast. Timed page visits on a desktop with a good connection
took about 190–380 ms with almost no layout shift, so page speed alone
doesn't explain it. Saving forms and phones weren't part of that test. The
code points to these likely causes:

- **The whole page is replaced on every click and save.** No page uses
  Turbo's morphing, and nothing stays in place between pages, including
  the sidebar.
- **Some actions do a real full reload.** There are 19 Turbo opt-outs
  across 14 files, including the dashboard, calendar, time clock and
  sidebar. Some are needed, such as sign-in and external login providers.
  Others may not be.
- **The dashboard appears twice.** On a return visit it draws a cached
  copy, then replaces it about half a second later.
- **Dashboard pieces arrive late.** The calendar and widgets load after
  the page, with no space held for them.
- **The first load is heavy.** About 70 files and 4.3 MB uncompressed,
  including all of Font Awesome and the web fonts from outside CDNs.

GatherPack is also only partly a PWA. It has a manifest that opens without
the browser bar, but its short name is blank, and its service worker is
entirely commented out and never registered. It has no way to send a
notification to a phone. Reminders go by email, where they are easy to miss.

## What it does

- **Saves that keep your place.** Saving on a page and returning to it
  updates only what changed and keeps the scroll position.
- **A steady frame.** The header and sidebar stay still as pages change.
  Dashboard cards hold their space while they load.
- **No double draw.** Pages with live information don't show a stale copy
  first.
- **Faster first and repeat visits.** Fonts and icons are served by
  GatherPack and cached.
- **Install to the home screen.** A proper name and icon, and it opens
  full screen.
- **Phone notifications.** People can opt in to get reminders on their
  phones, such as a form due or a shift tomorrow, alongside email. iPhones
  allow this only after the app is installed, so the page explains how.

Offline use is deliberately left out. Cached pages could leave student and
family information on shared devices, and could keep showing things after
someone's access has changed. Without a connection, the app shows a plain
"you're offline" page.

## How it's built

- **Smoothness.** `turbo-rails` 2.0 already includes Turbo 8. Turn on morph
  and scroll preservation for same-page refreshes, mark the sidebar
  `data-turbo-permanent` with a small Stimulus controller to keep its active
  link correct, use `no-preview` on pages with live data, and add
  placeholders for late-loading cards. Review each Turbo opt-out and remove
  the ones no longer needed.
- **Assets.** Host Font Awesome and the fonts locally. Trimming icons isn't
  simple, because admins choose icons by name, so the full set stays and
  relies on caching.
- **Installable app.** Fill in the manifest, and register a service worker
  that caches only versioned CSS, JavaScript, fonts and icons, plus the
  offline page. It never caches signed-in pages. Turning the flag off also
  unregisters it, so a bad version can't get stuck on devices.
- **Notifications.** A new table stores each person's device subscriptions,
  using standard Web Push with no outside account required. Existing
  reminders, such as `FormScheduleJob` and `SignupReminderJob`, add it as a
  delivery channel. Messages carry a short title and a link, with no
  personal details on the lock screen. Permission is requested only after
  someone chooses to turn it on.

**Other options, if a need appears:**

- **A small JavaScript component on one screen**, for something like a
  drag-and-drop board. GatherPack already does this with FullCalendar and
  CodeMirror.
- **Hotwire Native**, which wraps these same pages in App Store apps. This
  makes sense only if Web Push proves inadequate, since it adds store
  accounts and reviews.
- **A separate front end** is the only option that means rewriting screens.
  It would be justified only by full offline use or a highly interactive app
  throughout, and GatherPack needs neither.

**Size:** Small to medium, in independent parts. Smoothness and assets need
no migrations and touch a few layouts and templates. Notifications need one
migration, one gem and new keys in server configuration. Flags off by default.

## Risks

- **Scripts that assume a fresh page.** Morphing and a permanent sidebar can
  disturb Stimulus controllers, Bootstrap menus and modals, and the calendar.
  Each needs testing, and morphing can be turned off per page.
- **Removing an opt-out that exists for a reason.** Each may be working around
  something undocumented, so remove them one at a time.
- **A stale service worker.** Caching mistakes are hard to undo on devices
  already running it. Keep what it caches small, and test the off switch before
  shipping.
- **Shared devices.** The kiosk stays out of the installable app and
  notifications, and signing out removes that device's subscription.
- **Notification fatigue.** Too many messages get them turned off, so people
  choose which reminders they want.

## First step

Reproduce the flicker before fixing it. Record the main tasks on a real phone
and on a desktop, including saving forms, and list exactly what flickers. Then
apply the smoothness changes one at a time and record them again. Install and
notifications follow as separate pieces of work.

## Adoption

Independent of the other features in this folder, and could ship first. The
smoothness and asset changes fix issues in core and are good candidates for
upstream. Notifications need a generic delivery channel that other features can
use, so reminders aren't each wired to it separately.
