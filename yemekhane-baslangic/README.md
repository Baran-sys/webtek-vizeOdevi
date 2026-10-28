# Yemekhane Otomasyonu · Başlangıç Paketi

Web Teknolojileri dönem ödevinin hazır altyapısı. Veritabanı şeması, örnek veri, kaynak-replika
replikasyonu, Redis ve Apache tek komutla çalışır. Sizin yazacağınız kısım **uygulama servisi ve arayüzdür**.

## Hızlı başlangıç

Gerekenler: Docker Desktop (Windows/macOS) ya da Docker Engine + Compose v2 (Linux), Git.

```bash
git clone <kendi-deponuz>
cd yemekhane-baslangic
docker compose up -d
docker compose ps -a
```

İlk açılış 1–2 dakika sürer (MySQL kurulumu + örnek veri + replika kopyası). Beklenen durum:

| Servis | Beklenen |
|---|---|
| mysql-primary | `Up (healthy)` |
| mysql-replica | `Up (healthy)` |
| redis | `Up (healthy)` |
| frontend | `Up (healthy)` |
| replica-setup | `Exited (0)` — işini yapıp çıkar, bu normaldir |

`replica-setup` yalnızca `docker compose ps -a` ile görünür (`-a` olmadan çıkmış container'lar listelenmez).

Tarayıcıda: <http://localhost:8080>

## Klasör yapısı

```
docker-compose.yml        servisler; uygulama servisi yorum satırında
db/init/01_sema.sql       12 tablo, 3 view, 4 stored procedure
db/init/02_ornek_veri.sql 30 kullanıcı, 52 yemek, 84 menü, ~365 rezervasyon
db/replica-setup.sh       replikayı bir kez kurar ve salt okunur yapar
apache/                   Apache 2.4 imajı ve yönlendirme ayarı (MVC / Web API)
frontend/                 Apache'nin sunduğu HTML/CSS (css/temel.css başlangıç stilleri)
```

`db/init` içindeki dosyalar **yalnızca veritabanı ilk kez oluşturulurken** çalışır. Sonradan
değiştirirseniz etkisini görmek için `docker compose down -v` ile sıfırlamanız gerekir.

## Bağlantı bilgileri

Container'lar birbirine **servis adı ve iç port** ile bağlanır. Dış portlar (3307, 3308) yalnızca
kendi bilgisayarınızdaki araçlar (DBeaver, MySQL Workbench, terminal) içindir.

| | Uygulamadan (container içi) | Bilgisayarınızdan |
|---|---|---|
| Yazma (kaynak) | `mysql-primary:3306` | `localhost:3307` |
| Okuma (replika) | `mysql-replica:3306` | `localhost:3308` |
| Redis | `redis:6379` | `localhost:6379` |
| Web | — | `localhost:8080` |

| Hesap | Kullanıcı | Şifre |
|---|---|---|
| Uygulama | `yemekhane_app` | `Uyg_2026` |
| Yönetim (root) | `root` | `yemekhane_kok` |
| Replikasyon | `repl` | `Repl_2026` |

Veritabanı adı: `yemekhane`. Bu şifreler ders ortamı içindir; gerçek bir sistemde koda yazılmaz.

## Test hesapları

Tüm kullanıcıların şifresi **`Yemek2026!`** (bcrypt, `$2a$`, cost 10).

| E-posta | Rol | Not |
|---|---|---|
| leyla.arslan@kampus.edu.tr | yönetici | yönetici paneli için |
| murat.kaya@kampus.edu.tr | personel | personel fiyatı |
| ayse.demir@ogr.kampus.edu.tr | öğrenci | bakiyesi 12,50 TL — "Bakiye yetersiz." hatasını denemek için |
| mehmet.yildiz@ogr.kampus.edu.tr | öğrenci | normal bakiye |

Diğer kullanıcılar: `SELECT eposta, rol, bakiye FROM kullanicilar;`

**Tarihler kurulum gününe göre üretilir.** Menüler kurulumdan 7 gün önce başlar, 6 gün sonrasına
kadar uzanır. Haftalar sonra yeni menü kalmadıysa yönetici panelinden menü ekleyin ya da
`docker compose down -v && docker compose up -d` ile veriyi bugüne göre yeniden üretin.

## Veritabanı

### Tablolar ve kurallar

| Tablo | Kural |
|---|---|
| `kullanicilar` | `bakiye >= 0` (CHECK); `ogrenci_no` yalnızca öğrencide dolu (CHECK) |
| `yemekhaneler` | kapasite, menü başına rezervasyon sınırıdır (Merkez 400, Mühendislik 60) |
| `ogunler` | `son_saat`: rezervasyon/iptal son saati; `servis_baslangic/bitis`: turnike aralığı |
| `menuler` | yemekhane + tarih + öğün başına tek menü; öğrenci ve personel fiyatı ayrı (yönetici personel fiyatı öder) |
| `rezervasyonlar` | kişi başına menü başına tek kayıt; iptal edilen kayıt yeniden rezervasyonda tekrar `aktif` olur |
| `bakiye_hareketleri` | `tutar` işaretlidir: yükleme/iade `+`, rezervasyon `−`. Her zaman `bakiye = SUM(tutar)` |
| `degerlendirmeler` | kişi başına menü başına tek oy, 1–5. "Yalnızca kullanılmış menü" kontrolü uygulamanındır |

### View'lar

- `v_menu_detay` — menüdeki her yemek için bir satır: yemekhane, öğün, `rezervasyon_son`, fiyatlar,
  yemek, kategori, `kategori_sira`, kalori, vejetaryen, `alerjenler` (ad listesi), `alerjen_idler`.
  Toplam kaloriyi uygulama toplar. Sıralama: `ORDER BY kategori_sira, yemek`.
- `v_menu_doluluk` — menü başına `kapasite`, `rezerve`, `bos_yer`, `doluluk_yuzde`, `rezervasyon_son`.
- `v_menu_puan` — menü başına `oy_sayisi`, `ortalama_puan` (oy yoksa NULL).

### Stored procedure'ler

Para hareketi yapan işlemleri veri katmanında SQL ile yeniden yazmayın; bu yordamları çağırın.

| Yordam | Parametreler | Başarıda dönen tek satır |
|---|---|---|
| `sp_rezervasyon_yap` | `kullanici_id, menu_id` | `rezervasyon_id, ucret, bakiye` |
| `sp_rezervasyon_iptal` | `kullanici_id, rezervasyon_id` | `rezervasyon_id, iade, bakiye` |
| `sp_bakiye_yukle` | `kullanici_id, tutar` (10–1000 TL) | `hareket_id, bakiye` |
| `sp_turnike_gecis` | `kullanici_id, yemekhane_id, zaman` | `rezervasyon_id, menu_id, ogun` |

Sözleşme:

- Her yordam kendi transaction'ını açar ve kapatır. **Çağrıyı ayrıca BEGIN/COMMIT içine almayın**,
  autocommit açıkken `CALL` edin.
- Hata durumunda `SQLSTATE 45000` (MySQL hata kodu **1644**) ve Türkçe mesaj döner. Mesajı
  değiştirmeden arayüze iletin. Olası mesajlar: `Bakiye yetersiz.`, `Bu menü için rezervasyon süresi doldu.`,
  `Bu menü için zaten rezervasyonunuz var.`, `Yemekhane kapasitesi dolu.`, `Rezervasyon bulunamadı.`,
  `Yalnızca aktif rezervasyonlar iptal edilebilir.`, `Bu rezervasyon için iptal süresi doldu.`,
  `Yükleme tutarı 10 ile 1000 TL arasında olmalıdır.`, `Kullanıcı bulunamadı.`, `Menü bulunamadı.`
- CHECK kısıtı ihlali (hata kodu 3819) bir programlama hatasıdır, kullanıcıya ham haliyle gösterilmez.
- `sp_turnike_gecis` için `zaman` NULL ise şu an kullanılır. Kullanılmış rezervasyon üretmek
  (örneğin değerlendirme ekranını denemek) için belirli bir an verebilirsiniz:

```sql
CALL sp_turnike_gecis(7, 1, CONCAT(CURDATE(), ' 12:15:00'));
```

Yordamlar yazma işlemidir; **kaynakta** (`mysql-primary`) çağrılır.

## Uygulama servisini ekleme (Aşama 2)

1. Kodunuzu ve `Dockerfile`'ı `uygulama/` klasörüne koyun. Uygulama container içinde **8000**
   portunu dinlesin (farklıysa `docker-compose.yml` içindeki `UYGULAMA_ADRES`'i değiştirin).
2. `docker-compose.yml` sonundaki `uygulama:` bloğunun yorumlarını kaldırın.
3. Uygulama bağlantı bilgilerini ortam değişkenlerinden okusun:
   `DB_YAZMA_HOST`, `DB_OKUMA_HOST`, `DB_PORT`, `DB_ADI`, `DB_KULLANICI`, `DB_SIFRE`, `REDIS_HOST`, `REDIS_PORT`.
4. Apache modunu seçin: `frontend` servisinde `command: ["httpd-foreground", "-D", "WEBAPI"]`
   - **WEBAPI**: `/api/...` uygulamaya gider, geri kalanı `frontend/` klasöründen sunulur.
     Uygulamanızın yolları `/api/` ile başlamalıdır.
   - **MVC**: `/css/`, `/img/`, `/js/`, `/hata/` Apache'den, geri kalan her şey uygulamadan gelir.
5. `docker compose up -d --build`

Uygulama henüz yoksa ya da çökmüşse Apache `frontend/hata/503.html` sayfasını gösterir.

## Doğrulama komutları (Aşama 1)

```bash
# Tüm servislerin durumu
docker compose ps -a

# Replikasyon durumu: Replica_IO_Running ve Replica_SQL_Running "Yes" olmalı
docker compose exec mysql-replica mysql -uroot -pyemekhane_kok -e "SHOW REPLICA STATUS\G"

# Kaynakta bakiye yükle, replikada gör
docker compose exec mysql-primary mysql -uyemekhane_app -pUyg_2026 yemekhane -e "CALL sp_bakiye_yukle(7, 100)"
docker compose exec mysql-replica mysql -uyemekhane_app -pUyg_2026 yemekhane -e "SELECT id, bakiye FROM kullanicilar WHERE id = 7"

# Replikaya yazma denemesi: read-only hatası beklenir (ERROR 1290)
docker compose exec mysql-replica mysql -uyemekhane_app -pUyg_2026 yemekhane -e "CALL sp_bakiye_yukle(7, 50)"

# Replika durdurulup başlatıldığında aradaki değişiklikleri yakalar
docker compose stop mysql-replica
docker compose exec mysql-primary mysql -uyemekhane_app -pUyg_2026 yemekhane -e "CALL sp_bakiye_yukle(7, 200)"
docker compose start mysql-replica
docker compose exec mysql-replica mysql -uyemekhane_app -pUyg_2026 yemekhane -e "SELECT id, bakiye FROM kullanicilar WHERE id = 7"

# Redis
docker compose exec redis redis-cli ping
```

Windows PowerShell'de de aynı komutlar çalışır. Komut çıktılarını rapora eklerken parolayı
komut satırına yazdığınız için çıkan uyarı satırını önemsemeyin.

## Migration (Aşama 4)

`04_degisiklik.sql` dosyasını `db/init/` klasörüne koyun. Böylece depoyu sıfırdan kuran biri
(`docker compose up -d`) değişikliği otomatik alır. Çalışan sistemde ise kaynağa elle uygulayın:

```bash
docker compose exec -T mysql-primary mysql -uroot -pyemekhane_kok yemekhane < db/init/04_degisiklik.sql
```

Replikaya ayrıca uygulamayın; değişiklik replikasyonla geçer. `03` numarası boş bırakılmıştır.

## Sıfırlama

```bash
docker compose down -v      # container'lar ve TÜM veri silinir
docker compose up -d        # şema ve örnek veri bugüne göre yeniden kurulur
```

## Sık sorunlar

**`replica-setup` Exited (1)** — Günlüğe bakın: `docker compose logs replica-setup`. Çoğu zaman
yarım kalmış bir ilk kurulumdur; `docker compose down -v && docker compose up -d` ile düzelir.

**`bash\r: No such file or directory` ya da `$'\r': command not found`** — Windows'ta Git satır
sonlarını CRLF'ye çevirmiş. Depodaki `.gitattributes` bunu önler; dosyayı düzenleyicinizde LF olarak
kaydedin (VS Code sağ alt köşe: CRLF → LF) ve tekrar `docker compose up -d` çalıştırın.

**`port is already allocated`** — Bilgisayarınızda aynı portu kullanan bir program var
(yerel MySQL, XAMPP, başka bir Redis). Ya o programı kapatın ya da `docker-compose.yml`'de soldaki
portu değiştirin (ör. `"3317:3306"`). Container'lar arası bağlantı etkilenmez.

**Uygulama veritabanına bağlanamıyor** — Container içinden `localhost:3307` kullanılmaz;
`mysql-primary:3306` ve `mysql-replica:3306` kullanılır.

**`Authentication plugin 'caching_sha2_password' cannot be loaded`** — MySQL 8.4'ün varsayılan
kimlik doğrulaması. Sürücünüzün güncel sürümünü kullanın (PHP 7.4+, MySqlConnector, mysql2,
MySQL Connector/J 8+, mysqlclient).

**Türkçe karakterler bozuk** — Bağlantıda karakter setini `utf8mb4` olarak belirtin.

**Rezervasyon son saati yanlış görünüyor** — MySQL saat dilimi `+03:00` ayarlıdır; uygulama
container'ında `TZ=Europe/Istanbul` tanımlıdır. Son saat karşılaştırmasını veritabanına bırakın
(`v_menu_doluluk.rezervasyon_son` ya da yordamın hatası).

**Replikada yeni veri hemen görünmüyor** — Replikasyon eşzamansızdır. Bunun uygulamanızdaki
etkisini ve çözümünü raporda açıklamanız isteniyor.
