#!/bin/bash
set -e

EPRINTS_ROOT=/opt/eprints3
ARCHIVE_ID=${EPRINTS_ARCHIVE_ID:-repo}

: "${DB_HOST:?DB_HOST wajib diisi (host database eksternal)}"
: "${DB_PORT:=3306}"
: "${DB_NAME:?DB_NAME wajib diisi}"
: "${DB_USER:?DB_USER wajib diisi}"
: "${DB_PASS:?DB_PASS wajib diisi}"
: "${EPRINTS_HOSTNAME:?EPRINTS_HOSTNAME wajib diisi (misal repo.example.com)}"
: "${EPRINTS_ADMIN_EMAIL:?EPRINTS_ADMIN_EMAIL wajib diisi}"

echo "[entrypoint] Menunggu database eksternal ${DB_HOST}:${DB_PORT} ..."
until mysqladmin ping -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" --silent >/dev/null 2>&1; do
  echo "[entrypoint] DB belum siap, mencoba lagi dalam 3 detik..."
  sleep 3
done
echo "[entrypoint] Database eksternal terhubung."

cd "$EPRINTS_ROOT"

if [ ! -d "archives/$ARCHIVE_ID" ]; then
  echo "[entrypoint] Membuat archive '$ARCHIVE_ID' dengan DB eksternal..."

  printf "%s\n" \
    "$EPRINTS_HOSTNAME" \
    "$EPRINTS_ADMIN_EMAIL" \
    "$DB_HOST" \
    "$DB_PORT" \
    "$DB_NAME" \
    "$DB_USER" \
    "$DB_PASS" \
    "n" \
    | perl bin/epadmin create "$ARCHIVE_ID"

  perl bin/generate_apacheconf || true
  perl bin/epadmin enable "$ARCHIVE_ID" || true
  chown -R www-data:www-data "$EPRINTS_ROOT/archives/$ARCHIVE_ID"
else
  echo "[entrypoint] Archive '$ARCHIVE_ID' sudah ada, lewati pembuatan ulang."
fi

exec "$@"