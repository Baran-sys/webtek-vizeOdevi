-- =====================================================================
-- Yemekhane Otomasyonu · Veritabanı şeması
-- 12 tablo, 3 view, 4 stored procedure
-- Bu dosya mysql-primary ilk kez başlarken otomatik çalışır.
-- Replika şemayı replica-setup üzerinden kaynaktan alır.
-- =====================================================================
SET NAMES utf8mb4;
USE yemekhane;

-- ---------------------------------------------------------------------
-- 1. Kullanıcılar
--    bakiye hiçbir zaman negatif olamaz.
--    ogrenci_no yalnızca rolü 'ogrenci' olanlarda dolu olur.
-- ---------------------------------------------------------------------
CREATE TABLE kullanicilar (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ad            VARCHAR(50)  NOT NULL,
    soyad         VARCHAR(50)  NOT NULL,
    eposta        VARCHAR(120) NOT NULL,
    sifre_hash    CHAR(60)     NOT NULL COMMENT 'bcrypt',
    rol           ENUM('ogrenci','personel','yonetici') NOT NULL,
    ogrenci_no    VARCHAR(12)  NULL,
    bakiye        DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    aktif         TINYINT(1)   NOT NULL DEFAULT 1,
    olusturma     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_kullanici_eposta (eposta),
    UNIQUE KEY uq_kullanici_ogrenci_no (ogrenci_no),
    CONSTRAINT ck_kullanici_bakiye CHECK (bakiye >= 0),
    CONSTRAINT ck_kullanici_ogrenci_no CHECK (
        (rol = 'ogrenci'  AND ogrenci_no IS NOT NULL) OR
        (rol <> 'ogrenci' AND ogrenci_no IS NULL)
    )
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. Yemekhaneler (kapasite, menü başına rezervasyon sınırıdır)
-- ---------------------------------------------------------------------
CREATE TABLE yemekhaneler (
    id        TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ad        VARCHAR(60)  NOT NULL,
    konum     VARCHAR(120) NULL,
    kapasite  SMALLINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_yemekhane_ad (ad),
    CONSTRAINT ck_yemekhane_kapasite CHECK (kapasite > 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. Öğünler
--    son_saat: o günün menüsü için rezervasyon ve iptal son saati
--    servis_baslangic / servis_bitis: turnike geçişinin kabul edildiği aralık
-- ---------------------------------------------------------------------
CREATE TABLE ogunler (
    id                TINYINT UNSIGNED PRIMARY KEY,
    ad                VARCHAR(20) NOT NULL,
    sira              TINYINT UNSIGNED NOT NULL,
    son_saat          TIME NOT NULL,
    servis_baslangic  TIME NOT NULL,
    servis_bitis      TIME NOT NULL,
    UNIQUE KEY uq_ogun_ad (ad)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4–5. Yemek kategorileri ve yemekler
--    Menüde yemekler kategori sırasına göre gösterilir.
-- ---------------------------------------------------------------------
CREATE TABLE yemek_kategorileri (
    id    TINYINT UNSIGNED PRIMARY KEY,
    ad    VARCHAR(40) NOT NULL,
    sira  TINYINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_kategori_ad (ad)
) ENGINE=InnoDB;

CREATE TABLE yemekler (
    id           SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    kategori_id  TINYINT UNSIGNED NOT NULL,
    ad           VARCHAR(80) NOT NULL,
    kalori       SMALLINT UNSIGNED NOT NULL COMMENT 'porsiyon başına kcal',
    vejetaryen   TINYINT(1) NOT NULL DEFAULT 0,
    UNIQUE KEY uq_yemek_ad (ad),
    CONSTRAINT fk_yemek_kategori FOREIGN KEY (kategori_id)
        REFERENCES yemek_kategorileri (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6–7. Alerjenler ve yemek-alerjen eşleşmesi (çoka çok)
-- ---------------------------------------------------------------------
CREATE TABLE alerjenler (
    id  TINYINT UNSIGNED PRIMARY KEY,
    ad  VARCHAR(40) NOT NULL,
    UNIQUE KEY uq_alerjen_ad (ad)
) ENGINE=InnoDB;

CREATE TABLE yemek_alerjenleri (
    yemek_id    SMALLINT UNSIGNED NOT NULL,
    alerjen_id  TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (yemek_id, alerjen_id),
    CONSTRAINT fk_ya_yemek   FOREIGN KEY (yemek_id)   REFERENCES yemekler (id)   ON DELETE CASCADE,
    CONSTRAINT fk_ya_alerjen FOREIGN KEY (alerjen_id) REFERENCES alerjenler (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 8–9. Menüler ve menü yemekleri
--    Yemekhane + tarih + öğün başına tek menü.
--    Öğrenci ve personel fiyatı ayrıdır (yönetici personel fiyatı öder).
-- ---------------------------------------------------------------------
CREATE TABLE menuler (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    yemekhane_id     TINYINT UNSIGNED NOT NULL,
    tarih            DATE NOT NULL,
    ogun_id          TINYINT UNSIGNED NOT NULL,
    ogrenci_fiyati   DECIMAL(8,2) NOT NULL,
    personel_fiyati  DECIMAL(8,2) NOT NULL,
    olusturma        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    guncelleme       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_menu (yemekhane_id, tarih, ogun_id),
    KEY ix_menu_tarih (tarih),
    CONSTRAINT fk_menu_yemekhane FOREIGN KEY (yemekhane_id) REFERENCES yemekhaneler (id),
    CONSTRAINT fk_menu_ogun      FOREIGN KEY (ogun_id)      REFERENCES ogunler (id),
    CONSTRAINT ck_menu_fiyat CHECK (ogrenci_fiyati >= 0 AND personel_fiyati >= 0)
) ENGINE=InnoDB;

CREATE TABLE menu_yemekleri (
    menu_id   INT UNSIGNED NOT NULL,
    yemek_id  SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (menu_id, yemek_id),
    CONSTRAINT fk_my_menu  FOREIGN KEY (menu_id)  REFERENCES menuler (id) ON DELETE CASCADE,
    CONSTRAINT fk_my_yemek FOREIGN KEY (yemek_id) REFERENCES yemekler (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 10. Rezervasyonlar
--    Kişi başına menü başına tek kayıt. İptal edilen kayıt yeniden
--    rezervasyonda tekrar 'aktif' yapılır (yeni satır açılmaz).
-- ---------------------------------------------------------------------
CREATE TABLE rezervasyonlar (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    kullanici_id     INT UNSIGNED NOT NULL,
    menu_id          INT UNSIGNED NOT NULL,
    durum            ENUM('aktif','kullanildi','iptal') NOT NULL DEFAULT 'aktif',
    ucret            DECIMAL(8,2) NOT NULL,
    olusturma        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    kullanma_zamani  DATETIME NULL,
    iptal_zamani     DATETIME NULL,
    UNIQUE KEY uq_rezervasyon (kullanici_id, menu_id),
    KEY ix_rezervasyon_menu_durum (menu_id, durum),
    CONSTRAINT fk_rez_kullanici FOREIGN KEY (kullanici_id) REFERENCES kullanicilar (id),
    CONSTRAINT fk_rez_menu      FOREIGN KEY (menu_id)      REFERENCES menuler (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 11. Bakiye hareketleri
--    tutar işaretlidir: yükleme ve iade pozitif, rezervasyon negatif.
--    Kural: kullanicilar.bakiye = SUM(bakiye_hareketleri.tutar)
-- ---------------------------------------------------------------------
CREATE TABLE bakiye_hareketleri (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    kullanici_id     INT UNSIGNED NOT NULL,
    tur              ENUM('yukleme','rezervasyon','iade') NOT NULL,
    tutar            DECIMAL(10,2) NOT NULL,
    rezervasyon_id   INT UNSIGNED NULL,
    aciklama         VARCHAR(150) NULL,
    olusturma        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_hareket_kullanici (kullanici_id, olusturma),
    CONSTRAINT fk_hareket_kullanici   FOREIGN KEY (kullanici_id)   REFERENCES kullanicilar (id),
    CONSTRAINT fk_hareket_rezervasyon FOREIGN KEY (rezervasyon_id) REFERENCES rezervasyonlar (id),
    CONSTRAINT ck_hareket_isaret CHECK (
        (tur IN ('yukleme','iade') AND tutar > 0) OR
        (tur = 'rezervasyon'       AND tutar < 0)
    )
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 12. Değerlendirmeler (kişi başına menü başına tek oy, 1–5)
--    "Yalnızca kullanılmış menü değerlendirilir" kuralı uygulamaya aittir.
-- ---------------------------------------------------------------------
CREATE TABLE degerlendirmeler (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    kullanici_id  INT UNSIGNED NOT NULL,
    menu_id       INT UNSIGNED NOT NULL,
    puan          TINYINT UNSIGNED NOT NULL,
    yorum         VARCHAR(500) NULL,
    olusturma     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_degerlendirme (kullanici_id, menu_id),
    CONSTRAINT fk_deg_kullanici FOREIGN KEY (kullanici_id) REFERENCES kullanicilar (id),
    CONSTRAINT fk_deg_menu      FOREIGN KEY (menu_id)      REFERENCES menuler (id),
    CONSTRAINT ck_deg_puan CHECK (puan BETWEEN 1 AND 5)
) ENGINE=InnoDB;


-- =====================================================================
-- VIEW'LAR
-- =====================================================================

-- Menüdeki her yemek için bir satır. Toplam kaloriyi uygulama toplar.
-- Sıralama için: ORDER BY ogun_sira, kategori_sira, yemek
CREATE VIEW v_menu_detay AS
SELECT
    m.id                AS menu_id,
    m.tarih,
    m.yemekhane_id,
    yh.ad               AS yemekhane,
    m.ogun_id,
    o.ad                AS ogun,
    o.sira              AS ogun_sira,
    TIMESTAMP(m.tarih, o.son_saat) AS rezervasyon_son,
    m.ogrenci_fiyati,
    m.personel_fiyati,
    y.id                AS yemek_id,
    y.ad                AS yemek,
    k.id                AS kategori_id,
    k.ad                AS kategori,
    k.sira              AS kategori_sira,
    y.kalori,
    y.vejetaryen,
    (SELECT GROUP_CONCAT(a.ad ORDER BY a.ad SEPARATOR ', ')
       FROM yemek_alerjenleri ya JOIN alerjenler a ON a.id = ya.alerjen_id
      WHERE ya.yemek_id = y.id)                     AS alerjenler,
    (SELECT GROUP_CONCAT(ya.alerjen_id ORDER BY ya.alerjen_id)
       FROM yemek_alerjenleri ya
      WHERE ya.yemek_id = y.id)                     AS alerjen_idler
FROM menuler m
JOIN yemekhaneler       yh ON yh.id = m.yemekhane_id
JOIN ogunler            o  ON o.id  = m.ogun_id
JOIN menu_yemekleri     my ON my.menu_id = m.id
JOIN yemekler           y  ON y.id  = my.yemek_id
JOIN yemek_kategorileri k  ON k.id  = y.kategori_id;

-- Menü başına doluluk. 'aktif' ve 'kullanildi' kapasiteden düşer, 'iptal' düşmez.
CREATE VIEW v_menu_doluluk AS
SELECT
    m.id            AS menu_id,
    m.tarih,
    m.yemekhane_id,
    yh.ad           AS yemekhane,
    m.ogun_id,
    o.ad            AS ogun,
    yh.kapasite,
    COALESCE(r.rezerve, 0)                          AS rezerve,
    yh.kapasite - COALESCE(r.rezerve, 0)            AS bos_yer,
    ROUND(100 * COALESCE(r.rezerve, 0) / yh.kapasite, 1) AS doluluk_yuzde,
    TIMESTAMP(m.tarih, o.son_saat)                  AS rezervasyon_son
FROM menuler m
JOIN yemekhaneler yh ON yh.id = m.yemekhane_id
JOIN ogunler      o  ON o.id  = m.ogun_id
LEFT JOIN (
    SELECT menu_id, COUNT(*) AS rezerve
      FROM rezervasyonlar
     WHERE durum IN ('aktif', 'kullanildi')
     GROUP BY menu_id
) r ON r.menu_id = m.id;

-- Menü başına oy sayısı ve ortalama puan (oy yoksa ortalama NULL).
CREATE VIEW v_menu_puan AS
SELECT
    m.id                     AS menu_id,
    COUNT(d.id)              AS oy_sayisi,
    ROUND(AVG(d.puan), 2)    AS ortalama_puan
FROM menuler m
LEFT JOIN degerlendirmeler d ON d.menu_id = m.id
GROUP BY m.id;


-- =====================================================================
-- STORED PROCEDURE'LER
-- Ortak sözleşme:
--   * Her yordam kendi transaction'ını açar ve kapatır. Uygulama tarafında
--     ayrıca BEGIN/COMMIT ile sarmayın (autocommit açıkken CALL edin).
--   * Hata durumunda SQLSTATE '45000' ve Türkçe bir mesaj döner.
--     Uygulama bu mesajı olduğu gibi arayüze iletmelidir.
--   * Başarılı çağrı tek satırlık bir sonuç kümesi döndürür.
-- =====================================================================
DELIMITER $$

-- ---------------------------------------------------------------------
-- sp_rezervasyon_yap(kullanici_id, menu_id)
-- Dönen satır: rezervasyon_id, ucret, bakiye
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rezervasyon_yap(
    IN p_kullanici_id INT UNSIGNED,
    IN p_menu_id      INT UNSIGNED
)
BEGIN
    DECLARE v_rol          VARCHAR(10)  DEFAULT NULL;
    DECLARE v_aktif        TINYINT      DEFAULT NULL;
    DECLARE v_bakiye       DECIMAL(10,2) DEFAULT NULL;
    DECLARE v_son          DATETIME     DEFAULT NULL;
    DECLARE v_kapasite     INT          DEFAULT NULL;
    DECLARE v_ogr_fiyat    DECIMAL(8,2) DEFAULT NULL;
    DECLARE v_per_fiyat    DECIMAL(8,2) DEFAULT NULL;
    DECLARE v_ucret        DECIMAL(8,2) DEFAULT NULL;
    DECLARE v_dolu         INT          DEFAULT 0;
    DECLARE v_mevcut_id    INT UNSIGNED DEFAULT NULL;
    DECLARE v_mevcut_durum VARCHAR(12)  DEFAULT NULL;
    DECLARE v_rez_id       INT UNSIGNED DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

    START TRANSACTION;

    -- Kullanıcı satırını kilitle (eşzamanlı bakiye işlemlerine karşı)
    SELECT rol, aktif, bakiye INTO v_rol, v_aktif, v_bakiye
      FROM kullanicilar WHERE id = p_kullanici_id FOR UPDATE;
    IF v_rol IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kullanıcı bulunamadı.';
    END IF;
    IF v_aktif = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Hesabınız pasif durumda.';
    END IF;

    -- Menü satırını kilitle (eşzamanlı kapasite kontrolüne karşı)
    SELECT TIMESTAMP(m.tarih, o.son_saat), yh.kapasite, m.ogrenci_fiyati, m.personel_fiyati
      INTO v_son, v_kapasite, v_ogr_fiyat, v_per_fiyat
      FROM menuler m
      JOIN ogunler o       ON o.id  = m.ogun_id
      JOIN yemekhaneler yh ON yh.id = m.yemekhane_id
     WHERE m.id = p_menu_id
       FOR UPDATE;
    IF v_son IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Menü bulunamadı.';
    END IF;
    IF NOW() >= v_son THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bu menü için rezervasyon süresi doldu.';
    END IF;

    SELECT id, durum INTO v_mevcut_id, v_mevcut_durum
      FROM rezervasyonlar
     WHERE kullanici_id = p_kullanici_id AND menu_id = p_menu_id
       FOR UPDATE;
    IF v_mevcut_durum IN ('aktif', 'kullanildi') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bu menü için zaten rezervasyonunuz var.';
    END IF;

    SELECT COUNT(*) INTO v_dolu
      FROM rezervasyonlar
     WHERE menu_id = p_menu_id AND durum IN ('aktif', 'kullanildi');
    IF v_dolu >= v_kapasite THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Yemekhane kapasitesi dolu.';
    END IF;

    SET v_ucret = IF(v_rol = 'ogrenci', v_ogr_fiyat, v_per_fiyat);
    IF v_bakiye < v_ucret THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bakiye yetersiz.';
    END IF;

    IF v_mevcut_id IS NULL THEN
        INSERT INTO rezervasyonlar (kullanici_id, menu_id, durum, ucret)
        VALUES (p_kullanici_id, p_menu_id, 'aktif', v_ucret);
        SET v_rez_id = LAST_INSERT_ID();
    ELSE
        -- Daha önce iptal edilmiş kayıt yeniden etkinleşir
        UPDATE rezervasyonlar
           SET durum = 'aktif', ucret = v_ucret, olusturma = NOW(),
               iptal_zamani = NULL, kullanma_zamani = NULL
         WHERE id = v_mevcut_id;
        SET v_rez_id = v_mevcut_id;
    END IF;

    UPDATE kullanicilar SET bakiye = bakiye - v_ucret WHERE id = p_kullanici_id;

    INSERT INTO bakiye_hareketleri (kullanici_id, tur, tutar, rezervasyon_id, aciklama)
    VALUES (p_kullanici_id, 'rezervasyon', -v_ucret, v_rez_id, 'Rezervasyon');

    COMMIT;

    SELECT v_rez_id AS rezervasyon_id, v_ucret AS ucret, v_bakiye - v_ucret AS bakiye;
END$$

-- ---------------------------------------------------------------------
-- sp_rezervasyon_iptal(kullanici_id, rezervasyon_id)
-- Son saat geçmediyse aktif rezervasyonu iptal eder, ücreti iade eder.
-- Dönen satır: rezervasyon_id, iade, bakiye
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rezervasyon_iptal(
    IN p_kullanici_id   INT UNSIGNED,
    IN p_rezervasyon_id INT UNSIGNED
)
BEGIN
    DECLARE v_sahip   INT UNSIGNED  DEFAULT NULL;
    DECLARE v_durum   VARCHAR(12)   DEFAULT NULL;
    DECLARE v_ucret   DECIMAL(8,2)  DEFAULT NULL;
    DECLARE v_son     DATETIME      DEFAULT NULL;
    DECLARE v_bakiye  DECIMAL(10,2) DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

    START TRANSACTION;

    SELECT bakiye INTO v_bakiye
      FROM kullanicilar WHERE id = p_kullanici_id FOR UPDATE;
    IF v_bakiye IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kullanıcı bulunamadı.';
    END IF;

    SELECT r.kullanici_id, r.durum, r.ucret, TIMESTAMP(m.tarih, o.son_saat)
      INTO v_sahip, v_durum, v_ucret, v_son
      FROM rezervasyonlar r
      JOIN menuler m ON m.id = r.menu_id
      JOIN ogunler o ON o.id = m.ogun_id
     WHERE r.id = p_rezervasyon_id
       FOR UPDATE;

    -- Başkasının rezervasyonu da "bulunamadı" sayılır (bilgi sızdırmamak için)
    IF v_sahip IS NULL OR v_sahip <> p_kullanici_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervasyon bulunamadı.';
    END IF;
    IF v_durum <> 'aktif' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Yalnızca aktif rezervasyonlar iptal edilebilir.';
    END IF;
    IF NOW() >= v_son THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bu rezervasyon için iptal süresi doldu.';
    END IF;

    UPDATE rezervasyonlar
       SET durum = 'iptal', iptal_zamani = NOW()
     WHERE id = p_rezervasyon_id;

    UPDATE kullanicilar SET bakiye = bakiye + v_ucret WHERE id = p_kullanici_id;

    INSERT INTO bakiye_hareketleri (kullanici_id, tur, tutar, rezervasyon_id, aciklama)
    VALUES (p_kullanici_id, 'iade', v_ucret, p_rezervasyon_id, 'Rezervasyon iptali');

    COMMIT;

    SELECT p_rezervasyon_id AS rezervasyon_id, v_ucret AS iade, v_bakiye + v_ucret AS bakiye;
END$$

-- ---------------------------------------------------------------------
-- sp_bakiye_yukle(kullanici_id, tutar)
-- Tek seferde 10–1000 TL arası yükleme.
-- Dönen satır: hareket_id, bakiye
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_bakiye_yukle(
    IN p_kullanici_id INT UNSIGNED,
    IN p_tutar        DECIMAL(10,2)
)
BEGIN
    DECLARE v_bakiye  DECIMAL(10,2) DEFAULT NULL;
    DECLARE v_aktif   TINYINT       DEFAULT NULL;
    DECLARE v_hareket INT UNSIGNED  DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

    IF p_tutar IS NULL OR p_tutar < 10 OR p_tutar > 1000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Yükleme tutarı 10 ile 1000 TL arasında olmalıdır.';
    END IF;

    START TRANSACTION;

    SELECT bakiye, aktif INTO v_bakiye, v_aktif
      FROM kullanicilar WHERE id = p_kullanici_id FOR UPDATE;
    IF v_bakiye IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kullanıcı bulunamadı.';
    END IF;
    IF v_aktif = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Hesabınız pasif durumda.';
    END IF;

    UPDATE kullanicilar SET bakiye = bakiye + p_tutar WHERE id = p_kullanici_id;

    INSERT INTO bakiye_hareketleri (kullanici_id, tur, tutar, aciklama)
    VALUES (p_kullanici_id, 'yukleme', p_tutar, 'Bakiye yükleme');
    SET v_hareket = LAST_INSERT_ID();

    COMMIT;

    SELECT v_hareket AS hareket_id, v_bakiye + p_tutar AS bakiye;
END$$

-- ---------------------------------------------------------------------
-- sp_turnike_gecis(kullanici_id, yemekhane_id, zaman)
-- Kart okutulduğunda o anki öğünün aktif rezervasyonunu 'kullanildi' yapar.
-- zaman NULL ise NOW() kullanılır; test için belirli bir an verilebilir:
--   CALL sp_turnike_gecis(5, 1, CONCAT(CURDATE(), ' 12:15:00'));
-- Dönen satır: rezervasyon_id, menu_id, ogun
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_turnike_gecis(
    IN p_kullanici_id INT UNSIGNED,
    IN p_yemekhane_id TINYINT UNSIGNED,
    IN p_zaman        DATETIME
)
BEGIN
    DECLARE v_zaman   DATETIME;
    DECLARE v_menu_id INT UNSIGNED DEFAULT NULL;
    DECLARE v_ogun    VARCHAR(20)  DEFAULT NULL;
    DECLARE v_rez_id  INT UNSIGNED DEFAULT NULL;
    DECLARE v_durum   VARCHAR(12)  DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

    SET v_zaman = COALESCE(p_zaman, NOW());

    START TRANSACTION;

    SELECT m.id, o.ad INTO v_menu_id, v_ogun
      FROM menuler m
      JOIN ogunler o ON o.id = m.ogun_id
     WHERE m.yemekhane_id = p_yemekhane_id
       AND m.tarih = DATE(v_zaman)
       AND TIME(v_zaman) BETWEEN o.servis_baslangic AND o.servis_bitis
     LIMIT 1;
    IF v_menu_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Şu an bu yemekhanede servis yok.';
    END IF;

    SELECT id, durum INTO v_rez_id, v_durum
      FROM rezervasyonlar
     WHERE kullanici_id = p_kullanici_id AND menu_id = v_menu_id
       FOR UPDATE;
    IF v_durum = 'kullanildi' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bu rezervasyon zaten kullanıldı.';
    END IF;
    IF v_durum IS NULL OR v_durum <> 'aktif' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bu öğün için aktif rezervasyonunuz yok.';
    END IF;

    UPDATE rezervasyonlar
       SET durum = 'kullanildi', kullanma_zamani = v_zaman
     WHERE id = v_rez_id;

    COMMIT;

    SELECT v_rez_id AS rezervasyon_id, v_menu_id AS menu_id, v_ogun AS ogun;
END$$

DELIMITER ;
