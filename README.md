# Yemekhane Otomasyonu · Web Teknolojileri Dönem Ödevi

**Öğrenci:** Baran Yıldız  
**Aşama:** 1 / 4 (Aşama 1: Altyapı ve Kaynak-Replika Doğrulama)  
**Etiket:** `asama-1`  

---

## 📌 Proje Genel Bakış

Bu proje, kampüs yemekhanesi için menü, rezervasyon ve bakiye işlemlerini yöneten; Docker tabanlı çoklu konteyner mimarisine sahip bir web otomasyon sistemidir.

### Sistem Mimarisi & Konteynerlar:
1. **mysql-primary:** Ana veritabanı (yazma işlemleri, saklı yordamlar).
2. **mysql-replica:** Salt-okunur yedek ve listeleme veritabanı (`--super-read-only`).
3. **replica-setup:** Kaynak-replika replikasyonunu otomatik başlatan ve kendini kapatan yardımcı servis.
4. **redis:** Önbellek ve oturum deposu.
5. **frontend:** Apache 2.4 web sunucusu (statik dosyalar ve ters vekil yönlendirmesi).
6. **uygulama:** (Aşama 2'de eklenecek MVC / Web API servisi).

---

## 🚀 Hızlı Başlangıç

Depo kökünde tek bir komut ile tüm altyapı ayağa kaldırılabilir:

```bash
git clone https://github.com/Baran-sys/webtek-vizeOdevi.git
cd webtek-vizeOdevi
docker compose up -d
docker compose ps -a
```

### Beklenen Servis Durumları:
| Servis | Durum | Portlar |
|---|---|---|
| `yemekhane-mysql-primary-1` | `Up (healthy)` | `3307:3306` |
| `yemekhane-mysql-replica-1` | `Up (healthy)` | `3308:3306` |
| `yemekhane-redis-1` | `Up (healthy)` | `6379:6379` |
| `yemekhane-frontend-1` | `Up (healthy)` | `8080:80` |
| `yemekhane-replica-setup-1` | `Exited (0)` | — |

---

## 🧪 Aşama 1: Doğrulama Komutları

Aşama 1 kapsamında föyde belirtilen tüm testler yapılmış ve doğrulanmıştır:

### 1. Replikasyon Sağlık Durumu
```bash
docker compose exec mysql-replica mysql -uroot -pyemekhane_kok -e "SHOW REPLICA STATUS\G"
```
* `Replica_IO_Running: Yes` ve `Replica_SQL_Running: Yes` olduğu, `Seconds_Behind_Source: 0` ile gecikmesiz çalıştığı teyit edildi.

### 2. Kaynakta Bakiye Yükleme ve Replikada Okuma
```bash
# Kaynakta bakiye yükle
docker compose exec mysql-primary mysql -uyemekhane_app -pUyg_2026 yemekhane -e "CALL sp_bakiye_yukle(7, 100)"

# Replikada bakiye kontrolü
docker compose exec mysql-replica mysql -uyemekhane_app -pUyg_2026 yemekhane -e "SELECT id, bakiye FROM kullanicilar WHERE id = 7"
```
* Kaynakta yapılan bakiye artışı anında replikaya yansıdı.

### 3. Replikaya Yazma Denemesi (Salt Okunur Koruma)
```bash
docker compose exec mysql-replica mysql -uyemekhane_app -pUyg_2026 yemekhane -e "CALL sp_bakiye_yukle(7, 50)"
```
* `ERROR 1290 (HY000): The MySQL server is running with the --super-read-only option` hatası ile yazma işlemi engellendi.

### 4. Replika Kesintisi ve Veri Yakalama (Catch-up)
```bash
docker compose stop mysql-replica
docker compose exec mysql-primary mysql -uyemekhane_app -pUyg_2026 yemekhane -e "CALL sp_bakiye_yukle(7, 200)"
docker compose start mysql-replica
docker compose exec mysql-replica mysql -uyemekhane_app -pUyg_2026 yemekhane -e "SELECT id, bakiye FROM kullanicilar WHERE id = 7"
```
* Replika yeniden açıldığında ikili günlükleri okuyarak aradaki farkı anında kapattı.

### 5. Redis Ping Doğrulaması
```bash
docker compose exec redis redis-cli ping
# Yanıt: PONG
```

---

## 📄 Rapor ve Ekran Görüntüleri

* **Detaylı Aşama 1 Raporu:** [`rapor/Asama_1_Raporu.pdf`](rapor/Asama_1_Raporu.pdf)
* **Ekran Görüntüleri Klasörü:** [`screenshots/`](screenshots/)
