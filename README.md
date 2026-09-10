# Audiobookshelf + Traefik + Let's Encrypt on Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This repository deploys Audiobookshelf (a self-hosted server for audiobooks, ebooks and podcasts, with apps on iOS and Android that keep your position in sync) behind Traefik with automatic Let's Encrypt TLS, with scheduled backups and a companion restore script.

## Getting started

```bash
# 1. Clone
git clone https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose
cd audiobookshelf-traefik-letsencrypt-docker-compose

# 2. Create the two Docker networks the stack expects
docker network create traefik-network
docker network create audiobookshelf-network

# 3. Copy the environment template and fill in required values
cp .env.example .env
$EDITOR .env
# ^ Required: AUDIOBOOKSHELF_HOSTNAME, TRAEFIK_HOSTNAME,
#   TRAEFIK_ACME_EMAIL, TRAEFIK_BASIC_AUTH.
#   Point AUDIOBOOKSHELF_LIBRARY_PATH at your library, or leave it and use
#   ./audiobooks.

# 4. Deploy
docker compose -f audiobookshelf-traefik-letsencrypt-docker-compose.yml -p audiobookshelf up -d
```

**Open the site and create your account immediately.** Audiobookshelf has no accounts until someone makes one, and the form is open to whoever reaches it first.

### The application lives at `/audiobookshelf`, and that is not a choice

Audiobookshelf serves itself under `/audiobookshelf` even on a hostname of its own. `ROUTER_BASE_PATH` looks like the setting that moves it, and clearing it does make the *server* answer at `/` — which is exactly the trap. The path is compiled into the browser bundle when the image is built; it is a literal string in `/app/client/dist/_nuxt/*.js`. So the client still asks for `/audiobookshelf/login`, which no longer exists, and you get a white page and "Server could not be reached" from a server that is entirely healthy.

This template leaves the default alone and has Traefik redirect the bare hostname into the application instead. Hand out either address; both land in the right place. CI asserts the redirect, and asserts that the served page still references `/audiobookshelf/_nuxt` — so if upstream ever does change this, the build says so rather than a user discovering it.

### What success looks like

```bash
docker compose -f audiobookshelf-traefik-letsencrypt-docker-compose.yml -p audiobookshelf ps
curl -s "https://${AUDIOBOOKSHELF_HOSTNAME}/status"
# {"app":"audiobookshelf","serverVersion":"2.36.0","isInit":false,…}
```

`ps` shows `audiobookshelf` and `traefik` healthy, `backups` running with no health check of its own, and `init-permissions` exited 0. `"isInit":false` means no account exists yet — go make one.

### Common first-deploy issues

- **Traefik answers `404 page not found` and its log says nothing.** That is almost never the router. Traefik does not route to a container whose health check is failing, so a broken probe looks exactly like a missing route. Check the health column in `ps`.
- **The server restarts in a loop, complaining it cannot write.** The uid it runs as does not own the volumes. `docker compose -p audiobookshelf logs init-permissions` says what that container did; it is the piece that makes the unprivileged uid work at all.
- **Podcast downloads or file renames silently do nothing.** The library is not writable by `AUDIOBOOKSHELF_UID`. See below — this is the one media template in this fleet that needs write access.
- **Cert issuance fails.** DNS has not propagated, or port 80 is not reachable from the internet.
- **Networks not found.** Step 2 was skipped.

## The library is read-write, unlike the other media templates here

The Jellyfin and Navidrome templates in this fleet mount your collection `:ro`, because those servers never write to it and read-only is free insurance. Audiobookshelf is different and it matters: **podcast episodes are downloaded into the library**, and the built-in file manager renames files to match the metadata it fetched. Mounted read-only, both stop working with no error a user would ever connect to the cause.

Which is why the server does not run as root. Every file it creates in your library belongs to whoever it runs as, and a library slowly filling with root-owned files on a directory you thought was yours is a bad discovery. Set `AUDIOBOOKSHELF_UID`/`GID` to a user that can read **and write** the library. CI asserts both halves: that the server is not uid 0, and that it can write to the mount.

## Why there is an `init-permissions` container

The image does not contain `/config` or `/metadata`, so Docker creates those mountpoints itself, owned by root. The server is deliberately unprivileged, and an unprivileged process cannot write a root-owned directory — so without help the container starts, fails to open its database, and restarts forever. Compose has no way to set the owner of a named volume, which is why this is a container and not a line of YAML.

It runs once, exits, and the server waits for it. It is idempotent: after the first start the owner already matches and the recursive `chown` is skipped entirely, so a metadata directory holding a hundred thousand cover images is not walked on every boot. It never touches your library.

It does, however, refuse to let the stack start if your library is not writable by that uid — reading the answer off the directory's mode bits and naming both fixes:

```
ERROR: the library directory is not writable by 1000:1000.

  It is owned by 0:0 with mode 500.

  Audiobookshelf WRITES to your library: podcast episodes are
  downloaded into it and the file manager renames files there.
  Without write access both stop working, and neither says why.

  Fix it one of two ways, on the host:
    chown -R 1000:1000 <your library path>
  or set AUDIOBOOKSHELF_UID and AUDIOBOOKSHELF_GID in .env to the
  owner it already has (id -u and id -g of that user).
```

Failing at deploy time with that message is the entire value. The alternative is a stack that comes up perfectly and stops downloading podcasts, and nobody notices for three weeks.

## Updating

`./update.sh` moves this checkout to the latest release tag — a combination this repository's CI has booted, upgraded from the previous release on the same volumes, and smoke-tested — and then runs `docker compose up -d`. It refuses to cross a major version unattended, refuses to run over local changes, and names any variable that became required since your version before anything has moved. `./update.sh --dry-run` says what would happen.

## Supply chain trust

Three images pinned to `tag@sha256:<digest>` as interpolation defaults in the compose `x-images` block:

- [`ghcr.io/advplyr/audiobookshelf`](https://github.com/advplyr/audiobookshelf/pkgs/container/audiobookshelf): the server
- [`traefik`](https://hub.docker.com/_/traefik): reverse proxy
- [`alpine`](https://hub.docker.com/_/alpine): the backups sidecar and the init container

`git pull` alone delivers the tested combination; an `*_IMAGE_TAG` variable in `.env` overrides deliberately.

Two override levels exist per image. `<PREFIX>_IMAGE_VERSION` in `.env` swaps only the version of that image (Compose then pulls the tag, without a digest) and leaves every other pin as tested; `<PREFIX>_IMAGE_TAG` replaces the whole reference, digest included. Nested defaults need Docker Compose v2.5 or newer (2022).

The daily `check-pin-freshness` CI job re-resolves each pin against its registry and compares the pinned Audiobookshelf and Traefik versions against the latest upstream releases. GitHub Actions are pinned by commit SHA; Dependabot keeps those fresh.

## Production checklist

- [ ] **Create your account immediately after deploy**, before anyone else can.
- [ ] **Turn on Audiobookshelf's own backup schedule** (Settings → Backups), with its path set to `/backups`. It is off in a fresh install. See below for why it matters.
- [ ] **Point `AUDIOBOOKSHELF_LIBRARY_PATH` at the real library** and confirm `AUDIOBOOKSHELF_UID` can write to it.
- [ ] **Regenerate the Traefik dashboard hash.** The one in `.env.example` is a placeholder.
- [ ] **Host-mount the backup volume.** By default the archives land in a named volume: if the host dies, they die with it.
- [ ] **Back up the library separately.** It is not in these archives and cannot sensibly be.

## Backups and restore

The `backups` container archives `/config` on a loop — a 30-minute warm-up, a 24-hour interval, 7-day retention, all overridable in `.env`. That is `absdatabase.sqlite`: users and their passwords, the libraries you defined, listening progress and bookmarks for everyone, API tokens, and podcast subscriptions with their schedules. `/metadata` is deliberately excluded — covers and waveforms are rebuilt from the books, and leaving them out is what keeps these archives small enough to keep many of them.

Each archive is written to a `.partial` name, **read back with `tar -tzf`**, and only then renamed. The read-back is not decoration: BusyBox tar, which is what an alpine image ships, returns exit code 1 both for "a file changed while I was reading it" and for "I could not write the output at all". Trusting the exit code alone renames an empty file into place and calls it a backup. This loop refuses to.

**Turn on Audiobookshelf's own scheduled backup as well, and point it at `/backups`.** A tar copies a live SQLite file while it is being written, and whether that copy restores is luck; Audiobookshelf's own export is a consistent snapshot. The two land in the same directory here on purpose, so one place is the whole answer to "where are the backups" and one retention sweep covers both. Treat the tar as the lower bound, not the only defence.

Restore a tar archive with the interactive script:

```bash
chmod +x ./*.sh
./audiobookshelf-restore-config.sh
```

It stops the server first: the database is written on every position update. Listening progress and users are back immediately afterwards; covers and waveforms regenerate on demand, so a full rescan is not needed.

## Resource limits

Every service carries memory and CPU limits plus reservations as compose-level defaults: the same values CI boots the stack under. What moves these numbers is scanning a large library and generating waveforms, not playback. Override any of them in `.env` and the override survives every `git pull`. If a service is OOM-killed, `docker inspect <container> --format '{{.State.OOMKilled}}'` says so.

## Container hardening

Every service runs with `security_opt: no-new-privileges:true` and `cap_drop: [ALL]`. Traefik adds back `NET_BIND_SERVICE`; the backups sidecar and the init container add back the three they need to write and own files. Audiobookshelf adds back nothing at all — it is Node serving HTTP and reading and writing files, and it needs no Linux capability once its port is unprivileged, which is the other reason the server was moved off port 80.

## Testing

The [Deployment Verification](https://github.com/heyvaldemar/audiobookshelf-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml?query=branch%3Amain) workflow runs on every push, pull request, and every day at 06:00 UTC: shellcheck and actionlint, Trivy scans of all three pinned images, the daily freshness check, and a deploy job that boots the stack with ephemeral credentials and then requires the server to report its own identity and version through Traefik, the bare hostname to redirect into `/audiobookshelf/`, the served page to reference `/audiobookshelf/_nuxt`, the server to be running as a non-root uid, the library mount to accept a write from that uid, an archive to be produced and to carry `absdatabase.sqlite` by name, eight backup and restore scenarios to pass, and Audiobookshelf to come back up on the config directory the restore test replaced underneath it.

### Backup and restore, proven

`tests/e2e-backup-restore.sh` runs against the live stack and is what CI executes after the smoke test. Three scenarios carry the weight. The archive must contain `config/absdatabase.sqlite` by name, not merely a directory. The restore roundtrip writes a file, waits for the archive that contains it, deletes it, restores, and asserts it came back. The failure test blocks the destination the loop is about to write to and asserts the loop says FAILED and leaves nothing behind that is named like a backup and does not open.

```bash
chmod +x tests/e2e-backup-restore.sh
./tests/e2e-backup-restore.sh
```

Run it on a staging copy, not on production: it stops the server and empties the config directory.

## Security notes

- Credentials are read from `.env` at deploy time; `.env` is gitignored and compose fails fast on missing required variables.
- The server runs as an unprivileged uid on an unprivileged port, with every Linux capability dropped.
- Audiobookshelf has no accounts until someone creates one, and no gate in front of that form.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
