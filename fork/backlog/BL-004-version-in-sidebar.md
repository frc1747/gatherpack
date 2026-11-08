# BL-004: Show the deployed version under "powered by GatherPack"

| | |
|---|---|
| Kind | upstream feature |
| Priority | low |
| Status | started (`feature/app-version`, see `FORK.md`) |
| Added | 2026-10-03 |
| Upstream base checked | `32e8023` |
| Planned branch | `feature/app-version` |
| Upstream issue / PR | none yet (fork-only for now, per Corey 2026-10-04) |

## Summary

Nothing in the running app says which build it is. To tell whether production is on `v0.0.0-hbr.4` or `v0.0.0-hbr.5`, you have to SSH to the server and check the image tag. We want the version shown in small text under the "powered by GatherPack" line at the bottom of the left sidebar, for example `0.0.0-hbr.5`, with the commit in a tooltip.

Any GatherPack deployment would find this useful, so it's written as an upstream feature with upstream naming. HBR's release tags (`v<upstream>-hbr.<n>`) come through the same mechanism with no fork-specific code.

## Where things are today (upstream `32e8023`)

- **The footer:** `app/views/layouts/_sidebar.html.erb`, lines 57–59:
  ```erb
  <footer class="col-12 footer-ad">
    <a href="https://gatherpack.com" target="_blank">powered by <%= image_tag "logo.svg", alt: "GatherPack" %> GatherPack</a>
  </footer>
  ```
  The same footer appears on the sign-in screens in `app/views/layouts/devise.html.erb`, lines 47–49.
- **No version anywhere:** there's no `VERSION` file, version constant, or `git describe` in `app/`, `config/`, `lib/`, or `bin/`.
- **The image has no git history:** `.dockerignore` excludes `/.git/`, so the running container can't work out its own version. It has to be passed in at build time.
- **The version is already known at build time, but only on the image's labels:** `.github/workflows/build.yml` (called from the `publish` job in `ci.yml`, line 136) runs `docker/metadata-action`. For a tag `v0.0.0-hbr.5` its `version` output is the tag. For a push to `main` it's `main`. Its labels include `org.opencontainers.image.version` and `.revision`, but labels are image metadata the Rails process can't read.
- **The fork uses upstream's files unchanged:** `Dockerfile`, `build.yml`, `ci.yml`, and both layouts are identical on `hbr/platform` and `upstream/main`, so this is purely an upstream change. HBR picks it up through a normal rebuild.

## Proposed design

1. **Dockerfile:** declare build args in the final stage and turn them into environment variables. Put them as late as possible so a new version doesn't invalidate the cached layers (gems, node modules, asset precompile):
   ```dockerfile
   ARG GATHERPACK_VERSION=""
   ARG GATHERPACK_REVISION=""
   ENV GATHERPACK_VERSION=$GATHERPACK_VERSION \
       GATHERPACK_REVISION=$GATHERPACK_REVISION
   ```
2. **`build.yml`, "Build and push by digest" step:** pass them in:
   ```yaml
   build-args: |
     GATHERPACK_VERSION=${{ steps.meta.outputs.version }}
     GATHERPACK_REVISION=${{ github.sha }}
   ```
   The build job's `meta` step has no custom `tags`, so its `version` is the raw ref name (`v0.0.0-hbr.5`, `main`). Strip a leading `v` in the app, or give the build job the same `tags:` list as the merge job so both report `0.0.0-hbr.5`. Check with a test publish before relying on either.
3. **A small reader in a new file**, e.g. `lib/gatherpack/version.rb` next to `features.rb`:
   - `GatherPack.version`: `ENV["GATHERPACK_VERSION"].presence`, else in development the output of `git describe --tags --always` (computed once and cached), else `nil`.
   - `GatherPack.revision`: `ENV["GATHERPACK_REVISION"]`, shortened to 7 characters.
4. **Sidebar:** under the "powered by" link, add `<div class="small text-muted">` with the version, and the revision as a `title` tooltip. Render nothing if the version is `nil`, so self-built images without the build args look the same as today.
5. **Sign-in screen (`devise.html.erb`): leave it out.** A version on a public page tells anyone which known bugs the site has. The sidebar only shows to signed-in users (`app/views/layouts/application.html.erb`, lines 37–39 render it only when `current_user.present?`). Confirm with upstream; they may also prefer admins only.

### Alternative without touching the image

Porygon already pins the release through `GATHERPACK_TAG` in `/home/team1747/gatherpack/.env`. The compose file could pass `GATHERPACK_VERSION: ${GATHERPACK_TAG}` to the web container, and steps 3–4 alone would show it. That's quicker, but the label can drift from the image actually running (someone edits one and not the other). It also needs a compose change that only the `team1747` account can make. Prefer baking it into the image. Use this only as a stopgap.

## Hooks

None. This adds no records, and nothing changes state at runtime, so there's no `CanBeHooked` model or `Hook.catalog` entry to add. The version is fixed for the life of a container. A "deployed" event would belong to whatever runs the deploy, not to the app.

## Tests

- `GatherPack.version` returns `GATHERPACK_VERSION` when set, strips a leading `v`, and returns `nil` when unset in production (stub `ENV`).
- Sidebar: renders the version and tooltip when set, and renders nothing extra when unset (a view or system test signed in as any user).
- Sign-in page doesn't show the version.
- Manually: build the image locally with `--build-arg GATHERPACK_VERSION=v9.9.9-test`, run it, and check the sidebar. Then confirm that a rebuild with a different version reuses the cached asset layer (watch the `assets:precompile` step).

## Fork strategy notes

- Upstream first: open a short issue ("show the running version in the sidebar") before the PR, as `STRATEGY.md` says. It's small, generic, and touches files upstream owns (`Dockerfile`, `build.yml`, `_sidebar.html.erb`), so it's a poor fit for carrying in the fork.
- If upstream declines, carrying it is cheap. Only `_sidebar.html.erb` would need an edit; the reader could live in an initializer and the build args in a fork workflow. Record the touched files in `FORK.md`.
- No migration, no flag needed (it's display-only and shows nothing when unset). If upstream wants it switchable, use a `Settings` toggle, off by default.

## Draft upstream issue

> **Show the running version in the sidebar**
>
> There's currently no way to tell from the app which release a deployment is running. You have to check the container image on the server. The release workflow already knows the version (`docker/metadata-action`'s `version` output) but only writes it to image labels, which the app can't read. Proposal: pass it (and the commit SHA) into the image as build args and environment variables, and show it in small text under "powered by GatherPack" for signed-in users. Nothing is shown when the variable isn't set, so self-built images are unaffected. Happy to send a PR.
