# EPrints di Docker dengan Database Eksternal

Setup ini menjalankan **EPrints 3.4** (Apache + Perl) di dalam container,
tetapi **tidak** menyertakan container MySQL/MariaDB. Database dianggap
sudah berjalan di luar stack ini (server terpisah, VM lain, managed DB
seperti RDS, atau container lain yang tidak dikelola compose ini).

## 1. Siapkan database eksternal terlebih dahulu

Di server MySQL/MariaDB eksternal, buat database dan user:

```sql
CREATE DATABASE eprints_repo CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'eprints_user'@'%' IDENTIFIED BY 'password_kuat';
GRANT ALL PRIVILEGES ON eprints_repo.* TO 'eprints_user'@'%';
FLUSH PRIVILEGES;
```

Pastikan juga:
- MySQL/MariaDB mengizinkan koneksi remote (`bind-address` bukan `127.0.0.1`).
- Firewall/security group mengizinkan port DB (default 3306) dari IP/host
  tempat container EPrints berjalan.
- `max_allowed_packet` cukup besar (EPrints menyarankan minimal 16M).

## 2. Siapkan folder host untuk data archive

Container memakai bind mount `/var/eprints` (bukan named volume Docker),
jadi folder ini harus ada dan permission-nya cocok dengan user `www-data`
(UID 33) di dalam container sebelum pertama kali start:

```bash
sudo mkdir -p /var/eprints
sudo chown -R 33:33 /var/eprints
```

## 3. Konfigurasi environment

```bash
cp .env.example .env
nano .env   # isi DB_HOST, DB_USER, DB_PASS, dst sesuai DB eksternal Anda
```

## 4. Build & jalankan

```bash
docker compose up -d --build
```

Saat pertama kali start, `entrypoint.sh` akan:
1. Menunggu database eksternal bisa dihubungi (`mysqladmin ping`).
2. Menjalankan `bin/epadmin create` untuk membuat archive baru, mengarahkan
   koneksi DB-nya ke host/kredensial eksternal dari `.env`.
3. Meng-generate konfigurasi Apache dan mengaktifkan archive.

Akses via `http://localhost:8081` (atau port lain sesuai `EPRINTS_HOST_PORT`
di `.env`).

> Jika port 80 di server sudah dipakai service lain, cukup ubah
> `EPRINTS_HOST_PORT` di `.env` ke port bebas (misal 8081, 8888, dst) —
> tidak perlu ubah `docker-compose.yml`. Port di dalam container tetap
> 80, hanya port di sisi host yang berubah.

## 5. Catatan penting

- **Urutan prompt `epadmin create`** bisa sedikit berbeda antar versi
  EPrints. Jika proses pembuatan archive gagal di log
  (`docker compose logs -f eprints`), jalankan interaktif dulu untuk
  memastikan urutan pertanyaannya:
  ```bash
  docker compose run --rm eprints bash
  cd /opt/eprints3
  perl bin/epadmin create repo
  ```
  lalu sesuaikan daftar `printf` di `entrypoint.sh`.
- Data archive (dokumen, konfigurasi, index) disimpan langsung di
  `/var/eprints` pada host (bind mount), jadi bisa langsung di-backup
  dengan tool backup biasa (rsync, tar, dll) tanpa perlu masuk ke
  Docker volume. Database sendiri sudah eksternal sehingga backup-nya
  dilakukan terpisah di sisi server database.
- Jika ingin memakai PostgreSQL alih-alih MySQL, EPrints 3.4 dukungannya
  terbatas — disarankan tetap pakai MySQL/MariaDB eksternal.
- Untuk produksi, tambahkan reverse proxy (nginx/traefik) + TLS di depan
  container ini, dan set `EPRINTS_HOSTNAME` sesuai domain publik.

## Struktur file

```
.
├── Dockerfile          # image EPrints (Apache + Perl + source dari GitHub)
├── docker-compose.yml  # service eprints, tanpa service DB
├── entrypoint.sh        # tunggu DB eksternal siap → buat archive
├── .env.example         # kredensial DB eksternal
└── README.md
```

Data archive EPrints (via bind mount) akan berada di `/var/eprints` pada
host, bukan di dalam Docker volume.