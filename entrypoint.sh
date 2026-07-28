#!/bin/bash
set -e

EPRINTS_ROOT=/opt/eprints3
ARCHIVE_ID=${EPRINTS_ARCHIVE_ID:-repo}
REP_TYPE=${EPRINTS_REP_TYPE:-pub}
EPRINTS_UID=${EPRINTS_UID:-1000}
EPRINTS_GID=${EPRINTS_GID:-1000}
EPRINTS_ARCHIVE_NAME=${EPRINTS_ARCHIVE_NAME:-Repository}
EPRINTS_ORG_NAME=${EPRINTS_ORG_NAME:-Organisation}
EPADMIN="$EPRINTS_ROOT/bin/epadmin"

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

ARCHIVE_DIR="$EPRINTS_ROOT/archives/$ARCHIVE_ID"

if [ ! -d "$ARCHIVE_DIR" ]; then
  echo "[entrypoint] Membuat scaffold archive '$ARCHIVE_ID' (tipe: $REP_TYPE) ..."

  su -s /bin/bash eprints -c "
    printf '%s\n' '$ARCHIVE_ID' 'no' 'no' | perl '$EPADMIN' create '$REP_TYPE'
  "

  if [ ! -d "$ARCHIVE_DIR" ]; then
    echo '[entrypoint] GAGAL: scaffold archive tidak terbentuk. Cek log epadmin create di atas.'
    exit 1
  fi

  echo "[entrypoint] Menulis cfg/cfg.d/10_core.pl (hostname, port) ..."
  cat > "$ARCHIVE_DIR/cfg/cfg.d/10_core.pl" <<EOF
\$c->{host} = "$EPRINTS_HOSTNAME";
\$c->{port} = 80;
\$c->{aliases} = [];
\$c->{securehost} = undef;
\$c->{secureport} = 443;
\$c->{http_root} = undef;
EOF

  echo "[entrypoint] Menulis cfg/cfg.d/adminemail.pl ..."
  cat > "$ARCHIVE_DIR/cfg/cfg.d/adminemail.pl" <<EOF
\$c->{adminemail} = '$EPRINTS_ADMIN_EMAIL';
EOF

  echo "[entrypoint] Menulis cfg/cfg.d/database.pl (koneksi ke DB eksternal) ..."
  cat > "$ARCHIVE_DIR/cfg/cfg.d/database.pl" <<EOF
\$c->{dbdriver} = "mysql";
\$c->{dbhost} = "$DB_HOST";
\$c->{dbport} = $DB_PORT;
\$c->{dbsock} = undef;
\$c->{dbname} = "$DB_NAME";
\$c->{dbuser} = "$DB_USER";
\$c->{dbpass} = "$DB_PASS";
\$c->{dbengine} = "InnoDB";
EOF

  echo "[entrypoint] Menulis phrase archive_name & organisation_name ..."
  mkdir -p "$ARCHIVE_DIR/cfg/lang/en/phrases"
  cat > "$ARCHIVE_DIR/cfg/lang/en/phrases/archive_name.xml" <<EOF
<?xml version="1.0" encoding="utf-8" standalone="no" ?>
<!DOCTYPE phrases SYSTEM "entities.dtd">
<epp:phrases xmlns="http://www.w3.org/1999/xhtml"
xmlns:epp="http://eprints.org/ep3/phrase">
<epp:phrase id="archive_name">$EPRINTS_ARCHIVE_NAME</epp:phrase>
<epp:phrase id="organisation_name">$EPRINTS_ORG_NAME</epp:phrase>
</epp:phrases>
EOF

  chown -R eprints:eprints "$ARCHIVE_DIR"

  echo "[entrypoint] Membuat tabel database ..."
  su -s /bin/bash eprints -c "perl '$EPADMIN' create_tables '$ARCHIVE_ID'"

  echo "[entrypoint] Mengimpor subjek standar ..."
  su -s /bin/bash eprints -c "perl '$EPRINTS_ROOT/bin/import_subjects' --verbose --force '$ARCHIVE_ID'" || true

  echo "[entrypoint] Membuat halaman statis ..."
  su -s /bin/bash eprints -c "perl '$EPRINTS_ROOT/bin/generate_static' --verbose '$ARCHIVE_ID'" || true

  echo "[entrypoint] Generate konfigurasi Apache ..."
  su -s /bin/bash eprints -c "perl '$EPRINTS_ROOT/bin/generate_apacheconf' --verbose" || true

  chown -R eprints:eprints "$ARCHIVE_DIR"

  echo "------------------------------------------------------------------"
  echo "[entrypoint] Archive '$ARCHIVE_ID' selesai dibuat."
  echo "[entrypoint] PENTING: belum ada user admin. Buat sekarang dengan:"
  echo "  docker compose exec eprints su -s /bin/bash eprints -c \\"
  echo "    \"perl $EPADMIN create_user $ARCHIVE_ID\""
  echo "------------------------------------------------------------------"
else
  echo "[entrypoint] Archive '$ARCHIVE_ID' sudah ada, lewati pembuatan ulang."
fi


if ! grep -qF "Include $EPRINTS_ROOT/cfg/apache.conf" /etc/apache2/apache2.conf; then
  echo "[entrypoint] Menambahkan Include $EPRINTS_ROOT/cfg/apache.conf ke apache2.conf ..."
  echo "Include $EPRINTS_ROOT/cfg/apache.conf" >> /etc/apache2/apache2.conf
fi
a2dissite 000-default.conf >/dev/null 2>&1 || true

exec "$@"