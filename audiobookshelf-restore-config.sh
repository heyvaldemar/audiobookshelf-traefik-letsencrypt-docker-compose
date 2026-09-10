#!/bin/bash

# Restore Audiobookshelf's config directory from one of the archives the
# `backups` container has taken.
#
# That directory is absdatabase.sqlite and the settings beside it: users and
# their passwords, the libraries you defined, listening progress and bookmarks
# for everyone, API tokens, and the podcast subscriptions with their download
# schedules.
#
#     chmod +x audiobookshelf-restore-config.sh
#     ./audiobookshelf-restore-config.sh
#
# The library itself is NOT in the archive and is not touched by this script.
# Neither is /metadata — covers, waveforms and cached metadata are rebuilt from
# the books, which is why the archive stays small enough to keep many of them.
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-audiobookshelf-traefik-letsencrypt-docker-compose.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-audiobookshelf}"
BACKUP_PATH="${DATA_BACKUPS_PATH:-/srv/audiobookshelf-config/backups}"
RESTORE_PATH="${DATA_PATH:-/config}"

dc() { docker compose -f "$COMPOSE_FILE" -p "$PROJECT" "$@"; }

APP_CONTAINER="$(dc ps -aq audiobookshelf | head -n 1)"
BACKUPS_CONTAINER="$(dc ps -aq backups | head -n 1)"
[ -n "$APP_CONTAINER" ] || { echo "the audiobookshelf container was not found — is the stack up?" >&2; exit 1; }
[ -n "$BACKUPS_CONTAINER" ] || { echo "the backups container was not found — is the stack up?" >&2; exit 1; }

echo "--> All available config backups:"
docker exec "$BACKUPS_CONTAINER" sh -c "ls -1 $BACKUP_PATH" || true
echo "--> Anything named 'absdatabase' above is Audiobookshelf's own scheduled"
echo "--> export, which is a consistent snapshot rather than a tar taken while"
echo "--> the database was live. Restore that one through Settings -> Backups."
echo "--> This script restores the tar archives."

echo "--> Copy and paste the backup name from the list above and press [ENTER]
--> Example: audiobookshelf-config-backup-YYYY-MM-DD_hh-mm.tar.gz"
echo -n "--> "
read -r SELECTED
[ -n "$SELECTED" ] || { echo "nothing selected, nothing restored" >&2; exit 1; }

if ! docker exec "$BACKUPS_CONTAINER" sh -c "tar -tzf '${BACKUP_PATH}/${SELECTED}' > /dev/null"; then
  echo "that file is not a readable tar archive — nothing has been stopped or deleted" >&2
  exit 1
fi
echo "--> $SELECTED was selected and reads as a valid archive"

echo "--> Stopping Audiobookshelf..."
docker stop "$APP_CONTAINER" > /dev/null

echo "--> Restoring the config directory..."
# The archive stores paths relative to /, so it extracts there. The directory
# is emptied first: a restore that merges leaves rows in the old database that
# the archive never had.
docker exec "$BACKUPS_CONTAINER" sh -c "rm -rf '${RESTORE_PATH:?}'/* && tar -zxpf '${BACKUP_PATH}/${SELECTED}' -C /"
echo "--> Config recovery completed."

echo "--> Starting Audiobookshelf..."
docker start "$APP_CONTAINER" > /dev/null
echo "--> Audiobookshelf answers once it has opened the restored database."
echo "--> Listening progress and users are back immediately. Covers and"
echo "--> waveforms regenerate on demand; a full rescan is not required."
