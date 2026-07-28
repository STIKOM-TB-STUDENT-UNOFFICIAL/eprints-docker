#!/bin/bash
set -e

EPRINTS_ROOT=/opt/eprints3
ARCHIVE_ID=${EPRINTS_ARCHIVE_ID:-repo}
REP_TYPE=${EPRINTS_REP_TYPE:-pub}
EPRINTS_UID=${EPRINTS_UID:-1000}
EPRINTS_GID=${EPRINTS_GID:-1000}

: "${DB_HOST:?DB_HOST wajib diisi (host database eksternal)}"
: "${DB_PORT:=3306}"
: "${DB_NAME:?DB_NAME wajib diisi}"
: "${DB_USER:?DB_USER wajib diisi}"
: "${DB_PASS:?DB_PASS wajib diisi}"
: "${EPRINTS_HOSTNAME:?EPRINTS_HOSTNAME wajib diisi (misal repo.example.com)}"
: "${EPRINTS_ADMIN_EMAIL:?EPRINTS_ADMIN_EMAIL wajib diisi}"

if ! getent group eprints >/dev/null 2>&1; then
  groupadd -g "$EPRINTS_GID" eprints
fi
if ! id -u eprints >/dev/null 2>&1; then
  useradd -u "$EPRINTS_UID" -g eprints -d "$EPRINTS_ROOT" -s /bin/bash eprints
fi

chown -R eprints:eprints "$EPRINTS_ROOT"

sed -i "s/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=eprints/" /etc/apache2/envvars
sed -i "s/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=eprints/" /etc/apache2/envvars

echo "[entrypoint] Menunggu database eksternal ${DB_HOST}:${DB_PORT} ..."
until mysqladmin ping -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" --silent >/dev/null 2>&1; do
  echo "[entrypoint] DB belum siap, mencoba lagi dalam 3 detik..."
  sleep 3
done
echo "[entrypoint] Database eksternal terhubung."

if [ ! -d "$EPRINTS_ROOT/archives/$ARCHIVE_ID" ]; then
  echo "[entrypoint] Membuat archive '$ARCHIVE_ID' dengan DB eksternal..."

  CLEAN_HOSTNAME=$(echo "$EPRINTS_HOSTNAME" | sed -e 's|^https*://||' -e 's|:[0-9]*$||' -e 's|/.*$||')
  if [[ "$CLEAN_HOSTNAME" != *.* ]]; then
    CLEAN_HOSTNAME="${CLEAN_HOSTNAME}.example.com"
  fi
  echo "[entrypoint] Hostname yang digunakan: '$CLEAN_HOSTNAME'"

  echo "[entrypoint] Memastikan database '$DB_NAME' tersedia..."
  mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" \
    -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
    || echo "[entrypoint] Peringatan: gagal membuat database otomatis, pastikan '$DB_NAME' sudah ada dan '$DB_USER' punya akses penuh ke dalamnya."

  TMP_SCRIPT=$(mktemp /tmp/eprints_create.XXXXXX.sh)
  cat > "$TMP_SCRIPT" <<EOF
set -e
cd "$EPRINTS_ROOT"

printf '%s\n' \
  "$ARCHIVE_ID" \
  "yes" \
  "$CLEAN_HOSTNAME" \
  "80" \
  "#" \
  "/" \
  "" \
  "$EPRINTS_ADMIN_EMAIL" \
  "$CLEAN_HOSTNAME" \
  "$CLEAN_HOSTNAME" \
  "yes" \
  "yes" \
  "$DB_NAME" \
  "$DB_HOST" \
  "$DB_PORT" \
  "#" \
  "$DB_USER" \
  "$DB_PASS" \
  "InnoDB" \
  "yes" \
  "no" \
| perl bin/epadmin create "$REP_TYPE" || true

echo "[entrypoint] Melanjutkan pembuatan tabel database..."
perl bin/epadmin create_tables "$ARCHIVE_ID"
echo "[entrypoint] Mengimpor subjek standar..."
perl bin/import_subjects --verbose --force "$ARCHIVE_ID" || true
echo "[entrypoint] Membuat halaman statis..."
perl bin/generate_static --verbose "$ARCHIVE_ID" || true
EOF

  chown eprints:eprints "$TMP_SCRIPT"
  chmod 700 "$TMP_SCRIPT"
  su -s /bin/bash eprints -c "bash '$TMP_SCRIPT'"
  rm -f "$TMP_SCRIPT"

  su -s /bin/bash eprints -c "cd '$EPRINTS_ROOT' && perl bin/generate_apacheconf" || true

  a2dissite 000-default.conf >/dev/null 2>&1 || true

  if [ -f /etc/apache2/sites-available/eprints.conf ]; then
    a2ensite eprints.conf >/dev/null 2>&1 || true
  fi

  chown -R eprints:eprints "$EPRINTS_ROOT/archives/$ARCHIVE_ID"
else
  echo "[entrypoint] Archive '$ARCHIVE_ID' sudah ada, lewati pembuatan ulang."
fi

exec "$@"