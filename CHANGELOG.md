# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

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
- **There is no Buffering middleware, deliberately.** Traefik streams bodies
  unless one is attached; attaching it is what turns buffering on, and `0` on
  its limits means *no size ceiling*, not *off*. Measured against a response
  that takes four seconds to produce: 0.03s to the first byte without it, 4.15s
  with it. What limits a long request is the entry point's `readTimeout`, 60
  seconds by default and set to zero here — which matters, because uploading an
  audiobook is one long request.

[Unreleased]: https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
