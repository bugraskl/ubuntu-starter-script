# ubuntu-starter-script

Ubuntu 24.04 LTS kurulu bir makineyi tek komutla görüntü işleme / HMI makinesine dönüştüren kurulum scripti.

| Bileşen | Ne kuruluyor | Kaynak |
|---|---|---|
| Python | Python 3.12, pip, venv, geliştirme başlık dosyaları | Ubuntu apt |
| Basler kamera | **pylon Software Suite 26.08.1** (pylon Viewer, USB3/GigE sürücüleri, udev kuralları) | Basler (.deb) |
| Basler Python | **pypylon** | PyPI → `/opt/venv` |
| Görüntü işleme | **OpenCV** (`opencv-python`), NumPy | PyPI → `/opt/venv` |
| PLC | **python-snap7** (Siemens S7) | PyPI → `/opt/venv` |
| Veritabanı bağlantısı | PyMySQL (Python → MySQL) | PyPI → `/opt/venv` |
| Arayüz | **Apache2 + PHP 8.3 + MySQL 8.0**, Composer | Ubuntu apt |
| Tarayıcı | **Chromium** | snap |
| Ek | SSH sunucusu, temel geliştirme araçları, kamera performans ayarları | Ubuntu apt |
| İsteğe bağlı | phpMyAdmin, kiosk modu, VS Code, OpenCV C++, Xorg, otomatik güncellemeleri kapatma | `config.env` |

## Hızlı başlangıç

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/bugraskl/ubuntu-starter-script.git
cd ubuntu-starter-script
nano config.local.env    # isteğe bağlı: config.env'deki değerlerden değiştirmek istedikleriniz
./install.sh
```

> Repo gizli olduğu için `git clone` GitHub kullanıcı adı ve şifre yerine bir **Personal Access Token** ister (GitHub → Settings → Developer settings → Tokens). Alternatif: repoyu ZIP olarak indirip makineye kopyalayın.

Script kendini `sudo` ile yeniden başlatır, şifrenizi bir kez sorar ve gerisini kendisi yapar. Kurulum bittiğinde bir özet yazar; özette **yeniden başlatın** diyorsa `sudo reboot` yapın (kamera ayarları, grup üyelikleri ve kiosk modu bunun ardından devreye girer).

Kurulum **arka planda bir sistem servisi** olarak çalışır; terminal sadece ilerlemeyi gösterir. Terminali ya da RustDesk/AnyDesk bağlantısını kapatmak kurulumu yarıda kesmez. Tekrar izlemek için:

```bash
tail -f /var/log/ubuntu-starter/install-*.log
```

> ⚠️ Kurulum bitene kadar bilgisayarı **kapatmayın / yeniden başlatmayın**. Sistem güncellemesi yarıda kesilirse yeni çekirdek açılmayabilir (GRUB menüsüne geri döner). Böyle olursa GRUB'da *Advanced options for Ubuntu* → eski çekirdeği seçerek açın ve `./install.sh` komutunu tekrar çalıştırın; script yarım kalan paketleri kendisi tamamlar.

> Script'i Windows'tan USB bellekle kopyalarsanız satır sonları bozulabilir. Bu durumda: `sed -i 's/\r$//' install.sh`

Kurulum günlüğü: `/var/log/ubuntu-starter/install-TARİH.log`

## Ayarlar (`config.env`)

Varsayılan ayarlar `config.env` dosyasındadır. **Bu dosyayı değiştirmeyin**; değiştirmek istediğiniz satırları aynı klasörde `config.local.env` dosyasına yazın. O dosya git'te takip edilmez ve `config.env`'deki değerlerin üzerine yazar; böylece `git pull` hiç çakışmaz. Örnek `config.local.env`:

```bash
DB_NAME="yeditek"
DB_USER="yeditek"
KIOSK_ENABLE=1
```

Her bileşen `1` (kur) / `0` (kurma) ile açılıp kapatılır. En önemlileri:

| Ayar | Varsayılan | Açıklama |
|---|---|---|
| `INSTALL_PYLON` | 1 | Basler pylon + pylon Viewer |
| `INSTALL_WEB` | 1 | Apache2 + PHP + MySQL |
| `INSTALL_PHPMYADMIN` | 0 | `http://localhost/phpmyadmin` |
| `INSTALL_CHROMIUM` | 1 | Chromium (snap) |
| `KIOSK_ENABLE` | 0 | Açılışta Chromium'u tam ekran `KIOSK_URL` ile başlat |
| `DB_NAME` / `DB_USER` / `DB_PASS` | app_db / app_user / *rastgele* | Uygulama veritabanı |
| `VENV_DIR` | /opt/venv | Python paketlerinin kurulduğu sanal ortam |
| `VENV_AUTO_ACTIVATE` | 1 | Her yeni terminal bu sanal ortamla açılır (`python`, `pip` doğrudan venv'i kullanır) |
| `DISABLE_WAYLAND` | 1 | Xorg oturumu: RustDesk/AnyDesk'te kopyala-yapıştır ve giriş ekranı erişimi için gerekli |
| `DISABLE_AUTO_UPDATES` | 0 | Üretim makinesinde otomatik güncellemeleri kapat |

Python paketleri `requirements.txt` dosyasından kurulur; listeye paket ekleyip `./install.sh --only python_packages` çalıştırmanız yeterli.

## Adımlar

```bash
./install.sh --list                           # adımları listele
./install.sh --only pylon                     # sadece pylon
./install.sh --only web,phpmyadmin            # birden fazla adım
./install.sh --skip chromium                  # bir adımı atla
```

| Adım | İçerik |
|---|---|
| `system_update` | apt update/full-upgrade, temel araçlar, saat dilimi |
| `python` | Python 3 + `/opt/venv` sanal ortamı |
| `web` | Apache2, PHP, MySQL, `.htaccess` desteği, veritabanı + kullanıcı |
| `phpmyadmin` | phpMyAdmin |
| `pylon` | pylon indir (~1 GB) ve kur |
| `camera_tuning` | USB-FS 1000 MB, GigE soket tamponu, gerçek zamanlı öncelik izni |
| `python_packages` | `requirements.txt` paketleri + kurulum doğrulaması |
| `chromium` | Chromium (snap) |
| `extras` | SSH, kullanıcı grupları (dialout, video, plugdev), isteğe bağlı paketler |
| `kiosk` | Otomatik oturum, ekran kapanmasını kapatma, Chromium tam ekran |

Script tekrar çalıştırılabilir: kurulu olanları atlar, bir adım hata verirse diğerlerine devam eder ve sonunda hangi adımın başarısız olduğunu gösterir.

## Kurulumdan sonra

- **Python:** yeni açılan her terminal `/opt/venv` sanal ortamıyla gelir; `python` ve `pip` doğrudan onu kullanır. Terminal dışından çalışacak programlarda (servis, otomatik başlatma, masaüstü kısayolu) etkinleştirmeye gerek yok, yorumlayıcıyı tam yoluyla verin: `/opt/venv/bin/python program.py` ya da dosyanın ilk satırına `#!/opt/venv/bin/python`.
- **pylon Viewer:** uygulama menüsünde *pylon Viewer* ya da `/opt/pylon/bin/pylonviewer`
- **Web arayüzü:** dosyaları `/var/www/html` içine koyun (kullanıcınız `www-data` grubunda, sudo gerekmez) → `http://localhost/`
- **MySQL bilgileri:** `~/ubuntu-starter-credentials.txt` (root için: `sudo mysql`)
- **Kiosk:** adres `/etc/ubuntu-starter/kiosk.conf`, kiosktan çıkmak için `Alt+F4`

## GigE kamera ağ ayarları (elle yapılmalı)

Hangi ağ kartına kamera bağlı olduğunu script bilemediği için bu ayarlar elle yapılır:

```bash
nmcli connection show                               # kamera kartının bağlantı adını bulun
sudo nmcli connection modify "Kablolu bağlantı 2" \
  ipv4.method manual ipv4.addresses 192.168.10.1/24 \
  802-3-ethernet.mtu 9000                           # sabit IP + jumbo frame
sudo nmcli connection up "Kablolu bağlantı 2"
sudo ethtool -G enp3s0 rx 4096                      # alma halka tamponu (destekliyorsa)
```

Ardından kameraya aynı alt ağdan IP verin (pylon Viewer → *pylon IP Configurator*) ve kamerada `GevSCPSPacketSize` değerini 8192–9000 yapın. pylon Viewer'daki *Statistics* bölümünde *Failed Buffer* ve *Buffer Underrun* sayıları 0 kalmalıdır.

> **Güvenlik duvarı (ufw) uyarısı:** GigE Vision görüntü akışı kameradan PC'ye UDP ile gelir. `ufw` açarsanız kamera ağ kartına izin vermeniz gerekir: `sudo ufw allow in on enp3s0`

## Notlar

- **OpenCV:** `opencv-python` PyPI'daki en güncel sürüm olan **5.x** olarak kurulur. Mevcut kodunuz OpenCV 4.x için yazıldıysa `requirements.txt` içinde `opencv-python<5` yazın.
- **python-snap7 3.x** artık C kütüphanesi kullanmayan saf Python sürümüdür; `snap7.client.Client` API'si korunmuştur. Eski davranışa ihtiyaç olursa `requirements.txt` içinde `python-snap7<3` yazın.
- **pylon indirme linki** Basler sitesinden alınmıştır. Link değişirse ya da makinede internet yoksa, Basler sitesinden *pylon … Linux x86 (64 Bit) Debian Installer Package* `.tar.gz` dosyasını indirip `downloads/` klasörüne koyun; script onu kullanır. Script pylon'u kurduğunda Basler'ın lisans koşulları geçerlidir.
- **Chromium** Ubuntu 24.04'te sadece snap olarak resmi destekleniyor. Kiosk modu açıkken snap otomatik güncellemesi durdurulur (`sudo snap refresh --unhold chromium` ile açılır).
- Script yalnızca **Ubuntu 24.04 LTS (amd64/arm64)** üzerinde test edilmiştir.
