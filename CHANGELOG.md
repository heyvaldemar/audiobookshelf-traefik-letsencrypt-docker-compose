# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Traefik's timeouts also answer to the fleet-wide names.**
  `TRAEFIK_READ_TIMEOUT`, `TRAEFIK_WRITE_TIMEOUT` and `TRAEFIK_IDLE_TIMEOUT` now
  set the HTTPS entry point's timeouts here as in every other Traefik template
  in the fleet. When set they win; `AUDIOBOOKSHELF_STREAM_TIMEOUT`, `AUDIOBOOKSHELF_IDLE_TIMEOUT` keep working exactly as before,
  and a deployment that sets neither gets the same defaults.

## [1.0.5] - 2026-09-23

### Fixed

- **CI had never run the restore script.** The test restored with its own
  copy of the commands. The script read `DATA_PATH` and `DATA_BACKUPS_PATH`
  from the shell that ran it rather than from `.env` or the stack, so a path
  set in `.env` was not the one it listed or cleared, and it cleared with
  `rm -rf dir/*`, which leaves every dotfile of the newer state in place. It
  now takes every path and name from the running backups container, accepts
  the backup file name as an argument, starts the application again whatever
  happens, and CI runs it: a file written before a backup and deleted after it
  must be back once that backup is restored.

### Changed

- **The freshness check has its own workflow, Pin Freshness.** It ran inside Deployment Verification, whose badge is the one at the top of this README. Across the fleet, nine red runs in ten were a pin one version behind - which the fleet's triage moves within the day - and a reader cannot tell that from a stack that does not boot. The badge now says whether the stack boots. The job itself is unchanged.

## [1.0.4] - 2026-09-21

### Security

- **`traefik:3.7` was rebuilt upstream**; the pin moved from `sha256:1c32e7c36820…` to `sha256:24841fe2de73…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.0.3] - 2026-09-19

### Security

- **`alpine:3.22` was rebuilt upstream**; the pin moved from `sha256:365499d9dccb…` to `sha256:5291449c3df7…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.0.2] - 2026-09-18

### Security

- **`traefik:3.7` was rebuilt upstream**; the pin moved from `sha256:f86a2cab1b5c…` to `sha256:1c32e7c36820…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.
- **`alpine:3.22` was rebuilt upstream**; the pin moved from `sha256:14358309a308…` to `sha256:365499d9dccb…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.0.1] - 2026-09-17

### Changed

- **`ghcr.io/advplyr/audiobookshelf:2.36.0` moved to `ghcr.io/advplyr/audiobookshelf:2.36.1`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.

## [1.0.0] - 2026-09-10

First release. A production deployment of Audiobookshelf behind Traefik, built
to the fleet standard established in
[keycloak-traefik-letsencrypt-docker-compose](https://github.com/heyvaldemar/keycloak-traefik-letsencrypt-docker-compose).

### Added

- **Audiobookshelf 2.36 behind Traefik with Let's Encrypt TLS.** Three images
  pinned by `tag@sha256:<digest>` in the compose `x-images` block: the server,
  Traefik, and a plain alpine used by both the backups sidecar and the init
  container.
- **A read-write library mount, against this fleet's own pattern.** Jellyfin and
  Navidrome mount your collection `:ro` because those servers never write to it.
  Audiobookshelf does: podcast episodes are downloaded into the library, and the
  built-in file manager renames files to match fetched metadata. Read-only
  breaks both with no error a user would connect to the cause.
- **A server that does not run as root**, which is the other half of that
  decision. Every file created in your library belongs to whoever the process
  is, and a library filling with root-owned files on a directory you thought was
  yours is a bad discovery. CI asserts both halves: not uid 0, and able to write
  the mount.
- **An `init-permissions` one-shot** that makes the three volumes writable by
  that uid before the server starts. The image does not contain `/config` or
  `/metadata`, so Docker creates those mountpoints owned by root, and Compose
  has no way to set the owner of a named volume — which is why this is a
  container and not a line of YAML. It is idempotent: after the first start the
  owner already matches and the recursive `chown` is skipped, so a metadata
  directory with a hundred thousand covers is not walked on every boot.
- **A root redirect into the application.** See the note below on
  `ROUTER_BASE_PATH`; the bare hostname would otherwise return a 404 from a
  healthy server. CI asserts the redirect *and* that the served page still
  references `/audiobookshelf/_nuxt`, so an upstream change surfaces as a build
  failure rather than as a user's white screen.
- **Compression as an allow-list, not a blanket.** An m4b is already compressed;
  gzipping it spends CPU on both ends to make the file marginally larger.
  `includedContentTypes` names the text types, so the interface is compressed
  and the audio never is.
- **A backup loop that reads its own archive back before naming it a backup.**
  Each cycle writes `.partial`, verifies it with `tar -tzf`, and only then
  renames. BusyBox tar returns exit code 1 both for "a file changed while I read
  it" and for "I could not write the output at all".
- **An archive checked for `absdatabase.sqlite` by name.** A tarball of
  `/config` that merely contains a directory would pass a weaker test and
  restore into a server that starts perfectly and has forgotten everyone.
- **A restore script that stops the server first**, because the database is
  written on every position update.
- **Deployment Verification workflow**, `update.sh`, container hardening with
  `cap_drop: ALL` on every service, resource limits and reservations, and a
  sixty-second `stop_grace_period`.

### Notes

- **The stack refuses to start if the library is not writable by the uid the
  server will run as.** The init container works that out from the directory's
  own mode bits and names both fixes. Without it, podcast downloads and file
  renames fail silently weeks later, with nothing in any log pointing back to a
  permission. The first CI run is what asked for this: the runner's checkout
  belongs to uid 1001, the server runs as 1000, and the write test caught it.
  The question is answered arithmetically rather than by writing a file,
  because the init container is root — a `touch` would succeed against a
  directory the server cannot write and would prove nothing.
- **`ROUTER_BASE_PATH` must not be cleared, and the reason is not obvious.**
  Audiobookshelf serves itself under `/audiobookshelf` even on a hostname of its
  own. Setting the variable to an empty string does make the *server* answer at
  `/`, which is exactly the trap: the path is compiled into the browser bundle
  when the image is built — a literal string in `/app/client/dist/_nuxt/*.js` —
  so the client still requests `/audiobookshelf/login`, which no longer exists.
  The result is a white page and "Server could not be reached" from a server
  that is entirely healthy. Traefik redirects the root instead.
- **The server is moved off port 80.** The image declares `PORT=80` and expects
  to run as root; an unprivileged process cannot bind it. Nothing is published
  to the host either way — Traefik reaches the container on its network — so the
  port number is internal and free to change.
- **The health check uses `wget`, not `curl`.** This image has no curl at all,
  so the line the rest of this fleet uses would fail silently and leave the
  container permanently unhealthy — which, because Traefik does not route to an
  unhealthy container, presents as a 404 with nothing in any log.
- **Audiobookshelf's own backup schedule is off in a fresh install, and this
  template puts its output where the archives go.** A tar copies a live SQLite
  file while it is being written, and whether that copy restores is luck;
  Audiobookshelf's export is a consistent snapshot. Both land in `/backups`, so
  one directory answers "where are the backups" and one retention sweep covers
  both. The README asks you to turn it on.
- **`expr` exits 1 when its result is zero.** The first version of that
  permission check split the mode digits with `expr substr`, under `set -e`. On
  a mode like 500 the third digit is `0`, `expr` printed it and exited 1, and
  the script ended before reaching the message that is the whole point of the
  check. It still refused to start — the safe direction — but it refused in
  silence. Parameter expansion now does the splitting, with no external command
  and no exit status to trip over.
- **A shell comment inside a folded YAML scalar swallows the code after it.**
  `>-` joins lines that share the base indentation, so a `#` comment written at
  that level ends up on the same line as the commands that followed it, and
  everything after the `#` is comment. The first draft of the init container
  lost its entire permission check that way, silently. There are no shell
  comments inside these folded commands now; the explanations live above the
  `command:` key, where YAML keeps them.
- **There is no Buffering middleware, deliberately.** Traefik streams bodies
  unless one is attached; attaching it is what turns buffering on, and `0` on
  its limits means *no size ceiling*, not *off*. Measured against a response
  that takes four seconds to produce: 0.03s to the first byte without it, 4.15s
  with it. What limits a long request is the entry point's `readTimeout`, 60
  seconds by default and set to zero here — which matters, because uploading an
  audiobook is one long request.

[Unreleased]: https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
