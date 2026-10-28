#!/bin/bash
# =====================================================================
# Replika kurulumu (bir kez çalışır, sonra çıkar)
#   1. Kaynakta replikasyon kullanıcısını oluşturur
#   2. Kaynağın anlık kopyasını (GTID bilgisiyle) replikaya yükler
#   3. GTID otomatik konumlandırma ile replikasyonu başlatır
#   4. Replikayı kalıcı olarak salt okunur yapar (SET PERSIST)
# Replika zaten kuruluysa hiçbir şey yapmadan başarıyla çıkar; bu yüzden
# "docker compose up -d" her çalıştığında güvenle yeniden tetiklenebilir.
# =====================================================================
set -euo pipefail

PRIMARY_HOST="${PRIMARY_HOST:-mysql-primary}"
PRIMARY_PORT="${PRIMARY_PORT:-3306}"
REPLICA_HOST="${REPLICA_HOST:-mysql-replica}"
REPLICA_PORT="${REPLICA_PORT:-3306}"
DB="${MYSQL_DATABASE:-yemekhane}"

export MYSQL_PWD="${MYSQL_ROOT_PASSWORD}"
P=(mysql --default-character-set=utf8mb4 -uroot -h "$PRIMARY_HOST" -P "$PRIMARY_PORT")
R=(mysql --default-character-set=utf8mb4 -uroot -h "$REPLICA_HOST" -P "$REPLICA_PORT")

log() { echo "[replica-setup] $*"; }

# --- 0. Zaten kurulu mu? ---------------------------------------------
if [ -n "$("${R[@]}" -N -e "SHOW REPLICA STATUS")" ]; then
    log "Replika zaten yapılandırılmış, işlem yapılmadı."
    exit 0
fi

# --- 1. Kaynakta örnek verinin yüklendiğinden emin ol -----------------
for i in {1..60}; do
    if "${P[@]}" -N -e "SELECT 1 FROM ${DB}.bakiye_hareketleri LIMIT 1" >/dev/null 2>&1; then
        break
    fi
    log "Kaynak veritabanı hazır değil, bekleniyor ($i)..."
    sleep 2
done

log "Kaynakta replikasyon kullanıcısı oluşturuluyor."
"${P[@]}" -e "
  CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED BY '${REPL_PASSWORD}';
  GRANT REPLICATION SLAVE ON *.* TO '${REPL_USER}'@'%';"

# --- 2. İlk kopya ------------------------------------------------------
log "Kaynağın anlık kopyası alınıyor."
mysqldump -uroot -h "$PRIMARY_HOST" -P "$PRIMARY_PORT" \
    --default-character-set=utf8mb4 \
    --single-transaction --set-gtid-purged=ON \
    --routines --triggers --events \
    --databases "$DB" > /tmp/ilk_kopya.sql

log "Kopya replikaya yükleniyor."
# Replikanın kendi GTID geçmişini temizle (8.4: yeni sözdizimi, 8.0: eski)
"${R[@]}" -e "RESET BINARY LOGS AND GTIDS" 2>/dev/null || "${R[@]}" -e "RESET MASTER"
"${R[@]}" < /tmp/ilk_kopya.sql

# Uygulama kullanıcısı kaynakta oluşturuldu ama o işlem kopyanın GTID'leri
# içinde "zaten uygulanmış" sayılır; replikada ayrıca açılır.
# Yazma yetkisi de verilir ki yazma denemesi yetki hatasıyla değil
# read-only hatasıyla reddedilsin (Aşama 1 doğrulaması).
"${R[@]}" -e "
  SET SESSION sql_log_bin = 0;
  CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
  GRANT ALL PRIVILEGES ON \`${DB}\`.* TO '${MYSQL_USER}'@'%';"

# --- 3. Replikasyonu başlat --------------------------------------------
log "Replikasyon başlatılıyor."
"${R[@]}" -e "
  CHANGE REPLICATION SOURCE TO
    SOURCE_HOST = '${PRIMARY_HOST}',
    SOURCE_PORT = ${PRIMARY_PORT},
    SOURCE_USER = '${REPL_USER}',
    SOURCE_PASSWORD = '${REPL_PASSWORD}',
    SOURCE_AUTO_POSITION = 1,
    GET_SOURCE_PUBLIC_KEY = 1;
  START REPLICA;"

# --- 4. Salt okunur ----------------------------------------------------
"${R[@]}" -e "SET PERSIST read_only = ON; SET PERSIST super_read_only = ON;"

# --- 5. Doğrula --------------------------------------------------------
for i in {1..30}; do
    durum=$("${R[@]}" -e "SHOW REPLICA STATUS\G")
    if [[ "$durum" == *"Replica_IO_Running: Yes"* && "$durum" == *"Replica_SQL_Running: Yes"* ]]; then
        log "Replikasyon çalışıyor (IO=Yes, SQL=Yes). Replika salt okunur."
        exit 0
    fi
    sleep 1
done

log "HATA: replikasyon başlamadı."
echo "$durum"
exit 1
