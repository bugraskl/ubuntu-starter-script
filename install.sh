#!/usr/bin/env bash
# =============================================================================
#  ubuntu-starter-script
#  Ubuntu 24.04 LTS için görüntü işleme / HMI makinesi kurulum scripti
#
#    - Python 3.12 + sanal ortam (venv)
#    - Basler pylon Software Suite (pylon Viewer) + pypylon
#    - OpenCV, python-snap7 (Siemens S7 PLC), NumPy, PyMySQL
#    - Apache2 + PHP 8.3 + MySQL 8.0 (+ isteğe bağlı phpMyAdmin)
#    - Chromium (+ isteğe bağlı kiosk modu)
#
#  Kullanım:
#    ./install.sh                  config.env ayarlarıyla her şeyi kurar
#    ./install.sh --only pylon     sadece belirtilen adım(lar)ı çalıştırır
#    ./install.sh --help           tüm seçenekler
# =============================================================================
set -Eeuo pipefail

# Türkçe (tr_TR) dil ayarında [A-Za-z] gibi aralıklar "i" ve "I" harflerini kapsamaz;
# karşılaştırma/sıralama kurallarını dilden bağımsız yap (mesajlar Türkçe kalır).
unset LC_ALL
export LC_COLLATE=C

readonly SCRIPT_VERSION="1.0.1"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_PATH SCRIPT_DIR

# Adımlar çalışma sırasıyla
readonly ALL_STEPS=(system_update python web phpmyadmin pylon camera_tuning python_packages chromium extras kiosk)

declare -A STEP_TITLE=(
  [system_update]="Sistem güncelleme ve temel araçlar"
  [python]="Python 3 ve sanal ortam (venv)"
  [web]="Apache2 + PHP + MySQL"
  [phpmyadmin]="phpMyAdmin"
  [pylon]="Basler pylon Software Suite (pylon Viewer)"
  [camera_tuning]="Kamera performans ayarları (USB3 / GigE)"
  [python_packages]="Python paketleri (pypylon, OpenCV, snap7...)"
  [chromium]="Chromium tarayıcı"
  [extras]="Ek ayarlar (SSH, kullanıcı grupları, isteğe bağlı paketler)"
  [kiosk]="Kiosk modu (Chromium otomatik tam ekran)"
)

# Her adımı açıp kapatan config.env değişkeni (boş = her zaman çalışır)
declare -A STEP_FLAG=(
  [system_update]=""
  [python]="INSTALL_PYTHON"
  [web]="INSTALL_WEB"
  [phpmyadmin]="INSTALL_PHPMYADMIN"
  [pylon]="INSTALL_PYLON"
  [camera_tuning]="CAMERA_TUNING"
  [python_packages]="INSTALL_PY_PACKAGES"
  [chromium]="INSTALL_CHROMIUM"
  [extras]=""
  [kiosk]="KIOSK_ENABLE"
)

readonly BASE_PACKAGES=(
  build-essential cmake pkg-config git curl wget ca-certificates gnupg
  software-properties-common lsb-release tzdata openssl unzip jq tree
  htop nano vim psmisc net-tools iputils-ping ethtool usbutils pciutils v4l-utils
)

readonly WEB_PACKAGES=(
  apache2 mysql-server
  php libapache2-mod-php php-cli php-mysql php-curl php-gd php-mbstring
  php-xml php-zip php-intl php-bcmath composer
)

# -----------------------------------------------------------------------------
#  Çıktı yardımcıları
# -----------------------------------------------------------------------------
if [[ -t 1 || ${UBUNTU_STARTER_COLOR:-0} == 1 ]]; then
  C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m'
else
  C_RESET="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
fi

log()     { printf '%s[%s]%s %s\n' "$C_BLUE" "$(date +%H:%M:%S)" "$C_RESET" "$*"; }
ok()      { printf '%s  ✔ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()    { printf '%s  ! %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
err()     { printf '%s  ✘ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
die()     { err "$*"; exit 1; }
section() { printf '\n%s%s==> %s%s\n' "$C_BOLD" "$C_BLUE" "$*" "$C_RESET"; }

usage() {
  cat <<EOF
ubuntu-starter-script v$SCRIPT_VERSION — Ubuntu 24.04 LTS kurulum scripti

Kullanım: ./install.sh [seçenekler]

Seçenekler:
  --only ADIM[,ADIM...]   Sadece bu adımları çalıştır (config.env bayraklarını yok sayar)
  --skip ADIM[,ADIM...]   Bu adımları atla
  --config DOSYA          Farklı bir ayar dosyası kullan (varsayılan: config.env)
  --foreground            Kurulumu arka plan servisi yerine doğrudan bu terminalde çalıştır
  --list                  Adımları listele
  -h, --help              Bu yardımı göster

Kurulum bir sistem servisi olarak arka planda çalışır; terminali ya da uzak
masaüstü bağlantısını kapatmak kurulumu yarıda kesmez.

Örnekler:
  ./install.sh
  ./install.sh --only pylon,python_packages
  ./install.sh --skip chromium

Kurulum günlüğü: /var/log/ubuntu-starter/
EOF
}

list_steps() {
  local s
  for s in "${ALL_STEPS[@]}"; do
    printf '  %-16s %s\n' "$s" "${STEP_TITLE[$s]}"
  done
}

# -----------------------------------------------------------------------------
#  Parametreler
# -----------------------------------------------------------------------------
ORIG_ARGS=("$@")
ONLY_STEPS=""
SKIP_STEPS=""
CONFIG_FILE="$SCRIPT_DIR/config.env"
FOREGROUND=0

need_value() { [[ -n ${2:-} && ${2:0:1} != "-" ]] || { echo "Hata: $1 bir değer bekliyor." >&2; exit 2; }; }

while (($#)); do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --list)    list_steps; exit 0 ;;
    --only)    need_value "$1" "${2:-}"; ONLY_STEPS=$2; shift 2 ;;
    --only=*)  ONLY_STEPS=${1#*=}; shift ;;
    --skip)    need_value "$1" "${2:-}"; SKIP_STEPS=$2; shift 2 ;;
    --skip=*)  SKIP_STEPS=${1#*=}; shift ;;
    --config)  need_value "$1" "${2:-}"; CONFIG_FILE=$2; shift 2 ;;
    --config=*) CONFIG_FILE=${1#*=}; shift ;;
    --foreground) FOREGROUND=1; shift ;;
    *) echo "Bilinmeyen parametre: $1" >&2; usage; exit 2 ;;
  esac
done

for s in ${ONLY_STEPS//,/ } ${SKIP_STEPS//,/ }; do
  [[ -n ${STEP_TITLE[$s]:-} ]] || { echo "Bilinmeyen adım: $s  (geçerli adımlar için: --list)" >&2; exit 2; }
done

# Root değilsek sudo ile yeniden başlat
if [[ $EUID -ne 0 ]]; then
  echo "Yönetici (root) yetkisi gerekiyor, sudo ile yeniden başlatılıyor..."
  exec sudo -E bash "$SCRIPT_PATH" "${ORIG_ARGS[@]}"
fi

# -----------------------------------------------------------------------------
#  Ayarlar: config.env -> config.local.env -> varsayılanlar
#  config.local.env git'te takip edilmez; makineye özel ayarlar oraya yazılır,
#  böylece 'git pull' ile gelen config.env güncellemeleri çakışmaz.
# -----------------------------------------------------------------------------
load_config() {
  # Windows'ta düzenlenmiş dosyalardaki CRLF satır sonlarını tolere et
  # shellcheck disable=SC1090
  source <(sed 's/\r$//' "$1")
}

if [[ -f $CONFIG_FILE ]]; then
  CONFIG_FILE="$(readlink -f "$CONFIG_FILE")"
  load_config "$CONFIG_FILE"
elif [[ $CONFIG_FILE != "$SCRIPT_DIR/config.env" ]]; then
  die "Ayar dosyası bulunamadı: $CONFIG_FILE"
fi
LOCAL_CONFIG_FILE="${CONFIG_FILE%.env}.local.env"
if [[ -f $LOCAL_CONFIG_FILE ]]; then
  load_config "$LOCAL_CONFIG_FILE"
fi

: "${TARGET_USER:=${SUDO_USER:-}}"
: "${TIMEZONE:=Europe/Istanbul}"
: "${UPGRADE_SYSTEM:=1}"
: "${INSTALL_PYTHON:=1}"
: "${INSTALL_WEB:=1}"
: "${INSTALL_PHPMYADMIN:=0}"
: "${INSTALL_PYLON:=1}"
: "${CAMERA_TUNING:=1}"
: "${INSTALL_PY_PACKAGES:=1}"
: "${INSTALL_CHROMIUM:=1}"
: "${INSTALL_SSH:=1}"
: "${INSTALL_VSCODE:=0}"
: "${INSTALL_OPENCV_CPP:=0}"
: "${DB_CREATE:=1}"
: "${DB_NAME:=app_db}"
: "${DB_USER:=app_user}"
: "${DB_PASS:=}"
: "${PHP_TIMEZONE:=$TIMEZONE}"
: "${VENV_DIR:=/opt/venv}"
: "${VENV_AUTO_ACTIVATE:=1}"
: "${PYTHON_REQUIREMENTS:=requirements.txt}"
: "${PYLON_VERSION:=26.08.1}"
: "${PYLON_URL_X86_64:=https://downloads-ctf.baslerweb.com/dg51pdwahxgw/2RfxolIRgwIS2XcOo6WUbR/8b92c4d22d355d6423a1e2adf6fa09be/pylon-26.08.1_linux-x86_64_debs.tar.gz}"
: "${PYLON_URL_AARCH64:=https://downloads-ctf.baslerweb.com/dg51pdwahxgw/5Js1NCjgyAD2Ew6K6VMEkI/f6a279b246f3d5f5d190fb60e4fb6cbb/pylon-26.08.1_linux-aarch64_debs.tar.gz}"
: "${PYLON_INSTALL_CODEMETER:=1}"
: "${PYLON_FORCE_REINSTALL:=0}"
: "${DOWNLOAD_DIR:=$SCRIPT_DIR/downloads}"
: "${USBFS_MEMORY_MB:=1000}"
: "${GIGE_RMEM_MAX:=16777216}"
: "${KIOSK_ENABLE:=0}"
: "${KIOSK_URL:=http://localhost/}"
: "${KIOSK_AUTOLOGIN:=1}"
: "${KIOSK_DISABLE_SCREEN_BLANK:=1}"
: "${CHROMIUM_HOLD_UPDATES:=$KIOSK_ENABLE}"
: "${DISABLE_WAYLAND:=1}"
: "${DISABLE_AUTO_UPDATES:=0}"
: "${ALLOW_UNSUPPORTED_OS:=0}"

[[ $DOWNLOAD_DIR = /* ]] || DOWNLOAD_DIR="$SCRIPT_DIR/$DOWNLOAD_DIR"
[[ $PYTHON_REQUIREMENTS = /* ]] || PYTHON_REQUIREMENTS="$SCRIPT_DIR/$PYTHON_REQUIREMENTS"

export DEBIAN_FRONTEND=noninteractive
# apt sonrası servisleri kendiliğinden yeniden başlatma (uzak masaüstü bağlantısı kopmasın),
# sadece listele; kurulum sonunda zaten yeniden başlatma öneriliyor.
export NEEDRESTART_MODE=l
export PIP_DISABLE_PIP_VERSION_CHECK=1
cd /

# -----------------------------------------------------------------------------
#  Günlük (log) ve geçici durum dosyaları
# -----------------------------------------------------------------------------
LOG_DIR=/var/log/ubuntu-starter
mkdir -p "$LOG_DIR"
LOG_FILE="${UBUNTU_STARTER_LOG:-$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log}"
STATE_DIR=""
NOTES_FILE=""

setup_logging() {
  exec > >(tee -a "$LOG_FILE") 2>&1
  STATE_DIR="$(mktemp -d /tmp/ubuntu-starter.XXXXXX)"
  NOTES_FILE="$STATE_DIR/notes"
  touch "$NOTES_FILE"
  trap on_exit EXIT
}

on_exit() {
  local rc=$?
  # Arka plan servisi olarak çalışıyorsak sonucu, izleyen terminale bildir
  if [[ -n ${UBUNTU_STARTER_STATUS:-} ]]; then
    echo "$rc" > "$UBUNTU_STARTER_STATUS"
  fi
  if [[ -n $STATE_DIR ]]; then
    rm -rf "$STATE_DIR"
  fi
}

note()        { printf '%s\n' "$*" >> "$NOTES_FILE"; }
need_reboot() { touch "$STATE_DIR/reboot"; }
is_on()       { [[ ${1:-0} == 1 || ${1:-} == true || ${1:-} == yes ]]; }

# -----------------------------------------------------------------------------
#  Sistem yardımcıları
# -----------------------------------------------------------------------------
has_systemd() { [[ -d /run/systemd/system ]]; }

svc_enable_start() {
  if has_systemd; then systemctl enable --now "$1"; else service "$1" start; fi
}

svc_restart() {
  if has_systemd; then systemctl restart "$1"; else service "$1" restart; fi
}

# Açılışta çalışan otomatik güncelleme apt kilidini tutuyorsa bitmesini bekle
apt_wait_lock() {
  command -v fuser >/dev/null 2>&1 || return 0
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
    if (( waited == 0 )); then
      warn "Başka bir apt/dpkg işlemi çalışıyor (muhtemelen otomatik güncelleme), bitmesi bekleniyor..."
    fi
    if (( waited >= 1800 )); then
      err "apt kilidi 30 dakikada açılmadı."
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

apt_get() {
  apt_wait_lock
  apt-get -y -o DPkg::Lock::Timeout=600 -o Acquire::Retries=3 \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

apt_install() { apt_get install "$@"; }

run_as_user() {
  runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" "$@"
}

# GNOME ayarını hedef kullanıcı için yaz (oturum açıksa onun D-Bus'ını kullanır)
user_gsettings() {
  local uid bus
  uid="$(id -u "$TARGET_USER")"
  bus="/run/user/$uid/bus"
  if [[ -S $bus ]]; then
    run_as_user env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" XDG_RUNTIME_DIR="/run/user/$uid" gsettings set "$@"
  else
    run_as_user dbus-run-session -- gsettings set "$@"
  fi
}

# /etc/gdm3/custom.conf [daemon] bölümüne anahtar=değer yaz
gdm_set() {
  local f=/etc/gdm3/custom.conf key=$1 val=$2
  [[ -f $f ]] || printf '[daemon]\n' > "$f"
  grep -q '^\[daemon\]' "$f" || printf '\n[daemon]\n' >> "$f"
  sed -i "/^[[:space:]]*${key}[[:space:]]*=/d" "$f"
  sed -i "/^\[daemon\]/a ${key}=${val}" "$f"
}

sql_escape() {
  local s=${1//\\/\\\\}
  printf '%s' "${s//\'/\'\'}"
}

# -----------------------------------------------------------------------------
#  Ön kontroller
# -----------------------------------------------------------------------------
preflight() {
  section "Ön kontroller"

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != "24.04" ]]; then
    if is_on "$ALLOW_UNSUPPORTED_OS"; then
      warn "Desteklenmeyen sistem: ${PRETTY_NAME:-?} (ALLOW_UNSUPPORTED_OS=1 ile devam ediliyor)"
    else
      die "Bu script Ubuntu 24.04 LTS için yazıldı. Bulunan: ${PRETTY_NAME:-?}"
    fi
  else
    ok "İşletim sistemi: $PRETTY_NAME"
  fi

  ARCH="$(dpkg --print-architecture)"
  case $ARCH in
    amd64|arm64) ok "Mimari: $ARCH" ;;
    *) die "Desteklenmeyen mimari: $ARCH (amd64 veya arm64 gerekli)" ;;
  esac

  [[ -n $TARGET_USER ]] || die "Hedef kullanıcı belirlenemedi. Scripti normal kullanıcınızla 'sudo' üzerinden çalıştırın ya da config.env içinde TARGET_USER ayarlayın."
  [[ $TARGET_USER != root ]] || die "Hedef kullanıcı root olamaz. config.env içinde TARGET_USER ile normal bir kullanıcı belirtin."
  id "$TARGET_USER" >/dev/null 2>&1 || die "Kullanıcı bulunamadı: $TARGET_USER"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  ok "Hedef kullanıcı: $TARGET_USER ($TARGET_HOME)"

  if timeout 20 getent hosts archive.ubuntu.com >/dev/null 2>&1 \
     && timeout 20 bash -c '</dev/tcp/pypi.org/443' 2>/dev/null; then
    ok "İnternet bağlantısı var"
  else
    die "İnternet bağlantısı yok ya da DNS çalışmıyor (archive.ubuntu.com / pypi.org erişilemedi)."
  fi

  local free_gb
  free_gb=$(( $(df -Pk / | awk 'NR==2 {print $4}') / 1024 / 1024 ))
  if (( free_gb < 10 )); then
    warn "Kök dizinde sadece ${free_gb} GB boş alan var; pylon ile birlikte ~10 GB önerilir."
  else
    ok "Boş disk alanı: ${free_gb} GB"
  fi

  ok "Ayar dosyası: $( [[ -f $CONFIG_FILE ]] && echo "$CONFIG_FILE" || echo "yok (varsayılanlar)" )"
  if [[ -f $LOCAL_CONFIG_FILE ]]; then
    ok "Makineye özel ayarlar: $LOCAL_CONFIG_FILE"
  fi
  ok "Günlük dosyası: $LOG_FILE"
}

# Önceki bir kurulum yarıda kesildiyse (bağlantı koptu, bilgisayar kapandı...) paketleri tamamla.
# Aksi halde apt hiçbir şey kurmaz ve yeni çekirdek açılış dosyası (initramfs) olmadan kalır.
repair_package_state() {
  local audit
  audit="$(dpkg --audit 2>/dev/null || true)"
  if [[ -z $audit ]]; then
    return 0
  fi

  section "Yarım kalmış paket kurulumu tamamlanıyor"
  warn "Önceki bir apt/dpkg işlemi yarıda kesilmiş, tamamlanıyor..."
  apt_wait_lock
  if ! dpkg --force-confdef --force-confold --configure -a || ! apt_get -f install; then
    die "Paket sistemi onarılamadı. Hata ayrıntısı yukarıda; elle denemek için:  sudo dpkg --configure -a"
  fi
  ok "Yarım kalan paketler tamamlandı"
  need_reboot
}

# -----------------------------------------------------------------------------
#  Arka plan servisi: kurulum terminalden/oturumdan bağımsız çalışır
# -----------------------------------------------------------------------------
detach_to_service() {
  local running
  running="$(systemctl list-units 'ubuntu-starter-*.service' --state=active --no-legend --plain 2>/dev/null | awk '{print $1}')"
  if [[ -n $running ]]; then
    local env_line running_log
    env_line="$(systemctl show -p Environment --value "$running" 2>/dev/null || true)"
    running_log="$(tr ' ' '\n' <<< "$env_line" | sed -n 's/^UBUNTU_STARTER_LOG=//p')"
    warn "Kurulum zaten arka planda çalışıyor ($running), ona bağlanılıyor."
    follow_service "$running" "$running_log"
  fi

  local unit color=0
  unit="ubuntu-starter-$(date +%Y%m%d-%H%M%S)"
  [[ -t 1 ]] && color=1
  local args=(--config "$CONFIG_FILE")
  [[ -n $ONLY_STEPS ]] && args+=(--only "$ONLY_STEPS")
  [[ -n $SKIP_STEPS ]] && args+=(--skip "$SKIP_STEPS")

  : > "$LOG_FILE"
  systemd-run --quiet --unit="$unit" --collect \
    --description="ubuntu-starter-script kurulumu" \
    --setenv=UBUNTU_STARTER_DETACHED=1 \
    --setenv=UBUNTU_STARTER_LOG="$LOG_FILE" \
    --setenv=UBUNTU_STARTER_STATUS="$LOG_FILE.status" \
    --setenv=UBUNTU_STARTER_COLOR="$color" \
    --setenv=SUDO_USER="$TARGET_USER" \
    bash "$SCRIPT_PATH" "${args[@]}"
  follow_service "$unit" "$LOG_FILE"
}

follow_service() {
  local unit=$1 log=$2 tail_pid rc=1
  printf '%s%sKurulum arka planda sistem servisi olarak çalışıyor (%s).%s\n' "$C_BOLD" "$C_GREEN" "$unit" "$C_RESET"
  printf '  Bu pencereyi ya da uzak masaüstü bağlantısını kapatsanız da kurulum devam eder.\n'
  printf '  Tekrar izlemek için:  tail -f %s\n' "$log"
  printf '%s  Kurulum bitene kadar bilgisayarı KAPATMAYIN ve YENİDEN BAŞLATMAYIN.%s\n\n' "$C_YELLOW" "$C_RESET"

  tail -n +1 -F "$log" 2>/dev/null &
  tail_pid=$!
  # shellcheck disable=SC2064
  trap "kill $tail_pid 2>/dev/null; printf '\nİzleme durduruldu, kurulum arka planda devam ediyor:  tail -f %s\n' '$log'; exit 0" INT TERM HUP

  while systemctl is-active --quiet "$unit"; do
    sleep 2
  done
  sleep 1
  kill "$tail_pid" 2>/dev/null || true
  wait "$tail_pid" 2>/dev/null || true

  if [[ -f $log.status ]]; then
    rc="$(< "$log.status")"
    rm -f "$log.status"
  fi
  exit "$rc"
}

# -----------------------------------------------------------------------------
#  ADIM: Sistem güncelleme ve temel araçlar
# -----------------------------------------------------------------------------
step_system_update() {
  log "Paket listeleri güncelleniyor..."
  apt_get update

  if is_on "$UPGRADE_SYSTEM"; then
    log "Kurulu paketler güncelleniyor (full-upgrade)..."
    apt_get full-upgrade
    if [[ -f /var/run/reboot-required ]]; then
      need_reboot
    fi
  fi

  log "Temel araçlar kuruluyor..."
  apt_install "${BASE_PACKAGES[@]}"

  if [[ -n $TIMEZONE ]]; then
    if [[ ! -e /usr/share/zoneinfo/$TIMEZONE ]]; then
      warn "Geçersiz saat dilimi, atlanıyor: $TIMEZONE"
    elif has_systemd; then
      timedatectl set-timezone "$TIMEZONE"
    else
      ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
      echo "$TIMEZONE" > /etc/timezone
    fi
    ok "Saat dilimi: $TIMEZONE"
  fi
}

# -----------------------------------------------------------------------------
#  ADIM: Python
# -----------------------------------------------------------------------------
step_python() {
  log "Python 3 ve geliştirme paketleri kuruluyor..."
  # libgl1 + libglib: opencv-python (cv2) için gerekli sistem kütüphaneleri
  apt_install python3 python3-pip python3-venv python3-dev python-is-python3 python3-tk \
    libgl1 libglib2.0-0t64

  # Ubuntu 24.04'te sistem Python'una pip ile paket kurulamaz (PEP 668),
  # bu yüzden tüm Python paketleri ayrı bir sanal ortama kurulur.
  mkdir -p "$VENV_DIR"
  chown -R "$TARGET_USER:" "$VENV_DIR"
  if [[ ! -x $VENV_DIR/bin/python ]]; then
    log "Sanal ortam oluşturuluyor: $VENV_DIR"
    run_as_user python3 -m venv "$VENV_DIR"
  fi
  run_as_user "$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel

  ok "$(python3 --version), venv: $VENV_DIR"

  # Her yeni terminalde venv'i otomatik etkinleştir (sadece hedef kullanıcı için;
  # sistem araçları ve root /usr/bin/python3 kullanmaya devam eder)
  local bashrc="$TARGET_HOME/.bashrc"
  [[ -f $bashrc ]] || touch "$bashrc"
  sed -i '/^# >>> ubuntu-starter venv >>>$/,/^# <<< ubuntu-starter venv <<<$/d' "$bashrc"
  if is_on "$VENV_AUTO_ACTIVATE"; then
    cat >> "$bashrc" <<EOF
# >>> ubuntu-starter venv >>>
# ubuntu-starter-script: Python sanal ortamını her terminalde otomatik etkinleştir
if [ -z "\${VIRTUAL_ENV:-}" ] && [ -f "$VENV_DIR/bin/activate" ]; then
    . "$VENV_DIR/bin/activate"
fi
# <<< ubuntu-starter venv <<<
EOF
    ok "Yeni açılan her terminalde $VENV_DIR otomatik etkin"
    note "python / pip komutları her terminalde doğrudan $VENV_DIR sanal ortamını kullanır."
  else
    note "Python sanal ortamını etkinleştirmek için:  source $VENV_DIR/bin/activate"
  fi
  chown "$TARGET_USER:" "$bashrc"
}

# -----------------------------------------------------------------------------
#  ADIM: Apache2 + PHP + MySQL
# -----------------------------------------------------------------------------
step_web() {
  log "Apache2, PHP ve MySQL kuruluyor..."
  apt_install "${WEB_PACKAGES[@]}"

  # .htaccess desteği, dizin listelemeyi kapatma, ServerName uyarısını giderme
  cat > /etc/apache2/conf-available/ubuntu-starter.conf <<'EOF'
# ubuntu-starter-script tarafından oluşturuldu
ServerName localhost

<Directory /var/www/html>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
  a2enconf -q ubuntu-starter
  a2enmod -q rewrite headers

  local php_ver
  php_ver="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  local sapi
  for sapi in apache2 cli; do
    [[ -d /etc/php/$php_ver/$sapi/conf.d ]] || continue
    cat > "/etc/php/$php_ver/$sapi/conf.d/99-ubuntu-starter.ini" <<EOF
; ubuntu-starter-script tarafından oluşturuldu
date.timezone = $PHP_TIMEZONE
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
EOF
  done

  svc_enable_start apache2
  svc_restart apache2
  svc_enable_start mysql

  # Kullanıcı /var/www/html içine sudo'suz dosya yazabilsin
  usermod -aG www-data "$TARGET_USER"
  chown -R "$TARGET_USER:www-data" /var/www/html
  find /var/www/html -type d -exec chmod 2775 {} +
  find /var/www/html -type f -exec chmod 0664 {} +
  note "Web dosyaları: /var/www/html  (adres: http://localhost/)"

  log "MySQL'in hazır olması bekleniyor..."
  local _
  for _ in $(seq 1 60); do
    mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
    sleep 1
  done
  mysqladmin --protocol=socket ping >/dev/null 2>&1 || { err "MySQL servisi başlamadı."; return 1; }

  if is_on "$DB_CREATE"; then
    setup_database
  fi

  ok "$(apache2 -v 2>/dev/null | sed -n 's/^Server version: //p')"
  ok "PHP $(php -r 'echo PHP_VERSION;')"
  ok "$(mysql --version)"
}

setup_database() {
  [[ $DB_NAME =~ ^[A-Za-z0-9_]+$ ]] || { err "DB_NAME sadece harf, rakam ve _ içerebilir: $DB_NAME"; return 1; }
  [[ $DB_USER =~ ^[A-Za-z0-9_]+$ ]] || { err "DB_USER sadece harf, rakam ve _ içerebilir: $DB_USER"; return 1; }

  local cred_file="$TARGET_HOME/ubuntu-starter-credentials.txt"
  local pass=$DB_PASS
  # Tekrar çalıştırmada aynı şifreyi koru
  if [[ -z $pass && -f $cred_file ]]; then
    pass="$(awk -F= '$1 == "DB_PASS" { print substr($0, index($0, "=") + 1); exit }' "$cred_file")"
  fi
  [[ -n $pass ]] || pass="$(openssl rand -hex 16)"

  log "Veritabanı ve kullanıcı oluşturuluyor: $DB_NAME / $DB_USER"
  local esc
  esc="$(sql_escape "$pass")"
  mysql --protocol=socket -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$esc';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$esc';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

  (
    umask 077
    cat > "$cred_file" <<EOF
# ubuntu-starter-script tarafından oluşturuldu — $(date '+%Y-%m-%d %H:%M')
# MySQL root kullanıcısı şifresizdir; sadece 'sudo mysql' ile bağlanılır.
DB_HOST=localhost
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$pass
EOF
  )
  chown "$TARGET_USER:" "$cred_file"
  ok "Veritabanı hazır, bilgiler: $cred_file"
  note "MySQL bağlantı bilgileri: $cred_file  (root için: sudo mysql)"
}

# -----------------------------------------------------------------------------
#  ADIM: phpMyAdmin
# -----------------------------------------------------------------------------
step_phpmyadmin() {
  command -v mysql >/dev/null 2>&1 || { err "Önce 'web' adımı (Apache/PHP/MySQL) kurulmalı."; return 1; }

  local pma_pass
  pma_pass="$(openssl rand -hex 16)"
  debconf-set-selections <<EOF
phpmyadmin phpmyadmin/dbconfig-install boolean true
phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2
phpmyadmin phpmyadmin/mysql/app-pass password $pma_pass
phpmyadmin phpmyadmin/app-password-confirm password $pma_pass
EOF
  apt_install phpmyadmin
  svc_restart apache2
  ok "phpMyAdmin: http://localhost/phpmyadmin"
  note "phpMyAdmin: http://localhost/phpmyadmin  (giriş: $DB_USER kullanıcısı ve credentials dosyasındaki şifre)"
}

# -----------------------------------------------------------------------------
#  ADIM: Basler pylon
# -----------------------------------------------------------------------------
step_pylon() {
  local parch url
  case $ARCH in
    amd64) parch=x86_64;  url=$PYLON_URL_X86_64 ;;
    arm64) parch=aarch64; url=$PYLON_URL_AARCH64 ;;
  esac

  local installed
  installed="$(dpkg-query -W -f='${Version}' pylon 2>/dev/null || true)"
  if [[ -n $installed && $installed == "$PYLON_VERSION"* ]] && ! is_on "$PYLON_FORCE_REINSTALL"; then
    ok "pylon $installed zaten kurulu, atlanıyor (yeniden kurmak için PYLON_FORCE_REINSTALL=1)"
    return 0
  fi

  mkdir -p "$DOWNLOAD_DIR"
  local archive="$DOWNLOAD_DIR/${url##*/}"
  if [[ ! -f $archive ]]; then
    # Elle indirilip downloads/ klasörüne konmuş bir arşiv varsa onu kullan
    local manual
    manual="$(find "$DOWNLOAD_DIR" -maxdepth 1 -type f -name "pylon*${parch}_debs.tar.gz" | sort -V | tail -n 1)"
    if [[ -n $manual ]]; then
      archive=$manual
      log "Yerel arşiv kullanılıyor: $archive"
    fi
  fi

  if [[ ! -f $archive ]]; then
    log "pylon $PYLON_VERSION indiriliyor (~1 GB, internet hızına göre birkaç dakika sürebilir)..."
    if ! curl -fL --retry 5 --retry-delay 10 --connect-timeout 30 -C - --progress-bar \
         -o "$archive.part" "$url"; then
      err "pylon indirilemedi: $url"
      err "Çözüm: https://www.baslerweb.com/en/downloads/software/ adresinden"
      err "  'pylon ... Linux ${parch} (Debian Installer Package)' dosyasını indirip"
      err "  $DOWNLOAD_DIR/ klasörüne koyun ve './install.sh --only pylon' çalıştırın."
      return 1
    fi
    mv "$archive.part" "$archive"
  fi
  chown -R "$TARGET_USER:" "$DOWNLOAD_DIR" 2>/dev/null || true

  local tmp
  tmp="$(mktemp -d /tmp/pylon.XXXXXX)"
  chmod 755 "$tmp"   # apt'nin _apt kullanıcısı .deb dosyalarını okuyabilsin
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  log "Arşiv açılıyor: ${archive##*/}"
  if ! tar -xzf "$archive" -C "$tmp"; then
    err "Arşiv bozuk görünüyor, siliniyor. Scripti tekrar çalıştırın."
    rm -f "$archive"
    return 1
  fi

  local debs=() cm=()
  mapfile -t debs < <(find "$tmp" -type f -name 'pylon_*.deb' | sort)
  (( ${#debs[@]} > 0 )) || { err "Arşivde pylon .deb paketi bulunamadı."; return 1; }
  if is_on "$PYLON_INSTALL_CODEMETER"; then
    # CodeMeter: pylon vTools lisanslaması için (Basler kurulum talimatıyla aynı)
    mapfile -t cm < <(find "$tmp" -type f -name 'codemeter*.deb' | sort)
    debs+=("${cm[@]}")
  fi

  # Eski elle kurulmuş /opt/pylon varsa üzerine yazılmasına izin ver (aksi halde kurulum soru sorar)
  echo "pylon pylon/overwrite_existing_install boolean true" | debconf-set-selections

  log "Kuruluyor: $(printf '%s ' "${debs[@]##*/}")"
  apt_install "${debs[@]}"

  if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
  fi

  ok "pylon $(dpkg-query -W -f='${Version}' pylon) kuruldu (/opt/pylon)"
  if [[ -x /opt/pylon/bin/pylonviewer ]]; then
    note "pylon Viewer: uygulama menüsünden ya da /opt/pylon/bin/pylonviewer"
  else
    warn "pylonviewer /opt/pylon/bin altında bulunamadı; uygulama menüsünü kontrol edin."
  fi
  need_reboot
}

# -----------------------------------------------------------------------------
#  ADIM: Kamera performans ayarları
# -----------------------------------------------------------------------------
step_camera_tuning() {
  # USB3 Vision: USB-FS bellek limiti (Linux varsayılanı 16 MB, Basler önerisi 1000 MB)
  cat > /etc/tmpfiles.d/ubuntu-starter-usbfs.conf <<EOF
# ubuntu-starter-script: Basler USB3 kameralar için USB-FS bellek limiti
w /sys/module/usbcore/parameters/usbfs_memory_mb - - - - $USBFS_MEMORY_MB
EOF
  local usbfs=/sys/module/usbcore/parameters/usbfs_memory_mb
  if [[ -w $usbfs ]] && echo "$USBFS_MEMORY_MB" > "$usbfs" 2>/dev/null; then
    ok "USB-FS bellek limiti: $(cat "$usbfs") MB"
  else
    warn "USB-FS limiti şimdi uygulanamadı; yeniden başlatınca etkin olacak."
  fi

  # GigE Vision: büyük soket alma tamponuna izin ver (pylon SocketBufferSize için)
  cat > /etc/sysctl.d/60-ubuntu-starter-gige.conf <<EOF
# ubuntu-starter-script: Basler GigE kameralar için alma tamponu üst sınırı
net.core.rmem_max = $GIGE_RMEM_MAX
EOF
  if sysctl -q -p /etc/sysctl.d/60-ubuntu-starter-gige.conf 2>/dev/null; then
    ok "net.core.rmem_max = $(sysctl -n net.core.rmem_max)"
  else
    warn "sysctl şimdi uygulanamadı; yeniden başlatınca etkin olacak."
  fi

  # pylon alma iş parçacığına gerçek zamanlı öncelik verilebilsin (GigE için önerilir)
  cat > /etc/security/limits.d/90-ubuntu-starter-camera.conf <<EOF
# ubuntu-starter-script: pylon ReceiveThreadPriority için gerçek zamanlı öncelik izni
$TARGET_USER  -  rtprio  99
EOF
  ok "Gerçek zamanlı öncelik izni verildi: $TARGET_USER"
  need_reboot
}

# -----------------------------------------------------------------------------
#  ADIM: Python paketleri
# -----------------------------------------------------------------------------
step_python_packages() {
  [[ -x $VENV_DIR/bin/python ]] || { err "Sanal ortam yok: $VENV_DIR — önce 'python' adımı çalışmalı."; return 1; }
  [[ -f $PYTHON_REQUIREMENTS ]] || { err "Paket listesi bulunamadı: $PYTHON_REQUIREMENTS"; return 1; }

  install -m 0644 -o "$TARGET_USER" "$PYTHON_REQUIREMENTS" "$VENV_DIR/requirements.txt"
  log "Paketler kuruluyor: $(sed -e 's/[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$VENV_DIR/requirements.txt" | tr '\n' ' ')"
  run_as_user "$VENV_DIR/bin/pip" install --upgrade -r "$VENV_DIR/requirements.txt"
  run_as_user "$VENV_DIR/bin/pip" freeze > "$VENV_DIR/requirements.lock.txt"
  chown "$TARGET_USER:" "$VENV_DIR/requirements.lock.txt"

  log "Paketler doğrulanıyor..."
  run_as_user "$VENV_DIR/bin/python" - <<'PY'
import importlib
from importlib.metadata import version, PackageNotFoundError

checks = [
    ("numpy", "numpy"),
    ("cv2", "opencv-python"),
    ("pypylon", "pypylon"),
    ("snap7", "python-snap7"),
    ("pymysql", "PyMySQL"),
]
failed = []
for module, dist in checks:
    try:
        importlib.import_module(module)
        try:
            ver = version(dist)
        except PackageNotFoundError:
            ver = "?"
        print(f"  ✔ {dist:<15} {ver}")
    except Exception as exc:
        failed.append(module)
        print(f"  ✘ {dist:<15} içe aktarılamadı: {exc}")

if "pypylon" not in failed:
    try:
        from pypylon import pylon
        devices = pylon.TlFactory.GetInstance().EnumerateDevices()
        print(f"  Bulunan Basler kamera sayısı: {len(devices)}")
        for d in devices:
            print(f"    - {d.GetFriendlyName()}")
    except Exception as exc:
        print(f"  Kamera taraması yapılamadı: {exc}")

raise SystemExit(1 if failed else 0)
PY
  note "Kurulu Python paket sürümleri: $VENV_DIR/requirements.lock.txt"
}

# -----------------------------------------------------------------------------
#  ADIM: Chromium
# -----------------------------------------------------------------------------
step_chromium() {
  # Ubuntu 24.04'te Chromium'un resmi paketi snap'tir (apt'deki chromium-browser da snap kurar)
  if ! command -v snap >/dev/null 2>&1; then
    apt_install snapd
  fi
  snap wait system seed.loaded

  if snap list chromium >/dev/null 2>&1; then
    ok "Chromium zaten kurulu"
  else
    log "Chromium (snap) kuruluyor..."
    snap install chromium
  fi

  if is_on "$CHROMIUM_HOLD_UPDATES"; then
    snap refresh --hold chromium
    ok "Chromium otomatik güncellemeleri durduruldu (açmak için: sudo snap refresh --unhold chromium)"
  fi
  ok "Chromium $(snap list chromium | awk 'NR == 2 {print $2}')"
}

# -----------------------------------------------------------------------------
#  ADIM: Ek ayarlar
# -----------------------------------------------------------------------------
step_extras() {
  # Seri port (dialout), kamera/video ve USB cihaz erişimi
  local g groups=()
  for g in dialout video plugdev; do
    getent group "$g" >/dev/null && groups+=("$g")
  done
  if (( ${#groups[@]} > 0 )); then
    usermod -aG "$(IFS=,; echo "${groups[*]}")" "$TARGET_USER"
    ok "$TARGET_USER şu gruplara eklendi: ${groups[*]}"
    note "Grup değişikliklerinin geçerli olması için oturumu kapatıp açın (ya da yeniden başlatın)."
  fi

  if is_on "$INSTALL_SSH"; then
    log "OpenSSH sunucusu kuruluyor..."
    apt_install openssh-server
    if has_systemd; then
      # 24.04'te ssh soket aktivasyonu ile çalışır
      systemctl is-active --quiet ssh.socket || systemctl is-active --quiet ssh \
        || systemctl enable --now ssh.socket 2>/dev/null || systemctl enable --now ssh
    else
      service ssh start || true
    fi
    ok "SSH açık (port 22)"
  fi

  if is_on "$INSTALL_OPENCV_CPP"; then
    log "OpenCV C++ geliştirme paketleri kuruluyor (libopencv-dev)..."
    apt_install libopencv-dev
    ok "libopencv-dev kuruldu"
  fi

  if is_on "$INSTALL_VSCODE"; then
    log "Visual Studio Code (snap) kuruluyor..."
    snap install code --classic
    ok "VS Code kuruldu"
  fi

  if is_on "$DISABLE_WAYLAND"; then
    if [[ -d /etc/gdm3 ]]; then
      gdm_set WaylandEnable false
      ok "Wayland kapatıldı, oturum X11 (Xorg) ile açılacak"
      need_reboot
    else
      warn "GDM bulunamadı, Wayland ayarı atlandı."
    fi
  fi

  if is_on "$DISABLE_AUTO_UPDATES"; then
    cat > /etc/apt/apt.conf.d/99-ubuntu-starter-no-auto-upgrade <<'EOF'
// ubuntu-starter-script: üretim makinesinde otomatik güncellemeler kapalı
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::Download-Upgradeable-Packages "0";
EOF
    ok "Otomatik (unattended) güncellemeler kapatıldı"
    note "Otomatik güncellemeler kapalı: sistemi ara sıra elle güncelleyin (sudo apt update && sudo apt upgrade)."
  fi
}

# -----------------------------------------------------------------------------
#  ADIM: Kiosk modu
# -----------------------------------------------------------------------------
step_kiosk() {
  dpkg -s gdm3 >/dev/null 2>&1 || { err "GDM/GNOME bulunamadı; kiosk modu için Ubuntu Desktop gerekli."; return 1; }
  [[ -x /snap/bin/chromium ]] || { err "Chromium kurulu değil — önce 'chromium' adımı çalışmalı."; return 1; }

  mkdir -p /etc/ubuntu-starter
  printf '# Kiosk modunda açılacak adres\nKIOSK_URL=%q\n' "$KIOSK_URL" > /etc/ubuntu-starter/kiosk.conf

  cat > /usr/local/bin/ubuntu-starter-kiosk <<'EOF'
#!/usr/bin/env bash
# ubuntu-starter-script: Chromium kiosk başlatıcısı
# Adres /etc/ubuntu-starter/kiosk.conf içinden okunur.
KIOSK_URL="http://localhost/"
# shellcheck disable=SC1091
[ -f /etc/ubuntu-starter/kiosk.conf ] && . /etc/ubuntu-starter/kiosk.conf

# Elektrik kesintisi vb. sonrası "Sayfaları geri yükle?" balonunu engelle
PREF="$HOME/snap/chromium/common/chromium/Default/Preferences"
if [ -f "$PREF" ]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/; s/"exit_type":"[^"]*"/"exit_type":"Normal"/' "$PREF"
fi

# Web sunucusu cevap verene kadar bekle (en fazla 60 sn)
for _ in $(seq 1 60); do
  curl -s -o /dev/null --max-time 2 "$KIOSK_URL" && break
  sleep 1
done

exec /snap/bin/chromium --kiosk --no-first-run --noerrdialogs --disable-infobars \
  --disable-session-crashed-bubble --disable-features=Translate \
  --password-store=basic --check-for-update-interval=31536000 "$KIOSK_URL"
EOF
  chmod 755 /usr/local/bin/ubuntu-starter-kiosk

  local autostart="$TARGET_HOME/.config/autostart"
  mkdir -p "$autostart"
  cat > "$autostart/ubuntu-starter-kiosk.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Kiosk (Chromium)
Comment=ubuntu-starter-script tarafından oluşturuldu
Exec=/usr/local/bin/ubuntu-starter-kiosk
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=3
EOF
  chown -R "$TARGET_USER:" "$TARGET_HOME/.config"
  ok "Kiosk otomatik başlatma ayarlandı: $KIOSK_URL"
  note "Kiosk adresini değiştirmek için: /etc/ubuntu-starter/kiosk.conf  (kiosktan çıkmak: Alt+F4)"

  if is_on "$KIOSK_AUTOLOGIN"; then
    gdm_set AutomaticLoginEnable true
    gdm_set AutomaticLogin "$TARGET_USER"
    ok "Otomatik oturum açma: $TARGET_USER"
  fi

  if is_on "$KIOSK_DISABLE_SCREEN_BLANK"; then
    local failed=0
    user_gsettings org.gnome.desktop.session idle-delay 0 || failed=1
    user_gsettings org.gnome.desktop.screensaver lock-enabled false || failed=1
    user_gsettings org.gnome.desktop.screensaver idle-activation-enabled false || failed=1
    user_gsettings org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'" || failed=1
    user_gsettings org.gnome.settings-daemon.plugins.power idle-dim false || failed=1
    user_gsettings org.gnome.desktop.notifications show-banners false || failed=1
    if (( failed )); then
      warn "Bazı ekran ayarları yazılamadı; Ayarlar > Güç bölümünden ekran kapanmayı 'Hiçbir zaman' yapın."
    else
      ok "Ekran kapanma, kilit ekranı ve bildirim balonları kapatıldı"
    fi
  fi

  if snap list chromium >/dev/null 2>&1; then
    snap refresh --hold chromium || true
  fi
  need_reboot
}

# -----------------------------------------------------------------------------
#  Adım çalıştırıcı ve özet
# -----------------------------------------------------------------------------
declare -a RESULTS=()

step_selected() {
  local step=$1 flag
  if [[ -n $ONLY_STEPS ]]; then
    [[ ",$ONLY_STEPS," == *",$step,"* ]] || return 1
  else
    flag=${STEP_FLAG[$step]}
    if [[ -n $flag ]] && ! is_on "${!flag}"; then
      return 1
    fi
  fi
  [[ ",$SKIP_STEPS," != *",$step,"* ]]
}

run_step() {
  local step=$1 rc start
  section "${STEP_TITLE[$step]}  [$step]"
  start=$SECONDS
  # Her adım ayrı bir alt kabukta çalışır: bir adım hata verirse diğerleri devam eder.
  set +e
  (
    set -Eeuo pipefail
    trap 'err "Hata: satır $LINENO: $BASH_COMMAND"' ERR
    "step_$step"
  )
  rc=$?
  set -e
  if (( rc == 0 )); then
    RESULTS+=("OK|$step|$((SECONDS - start))")
  else
    RESULTS+=("HATA|$step|$((SECONDS - start))")
    err "'$step' adımı başarısız oldu (ayrıntı için günlüğe bakın: $LOG_FILE)"
  fi
}

print_summary() {
  section "Özet"
  local r status step secs any_fail=0
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r status step secs <<< "$r"
    case $status in
      OK)   printf '  %s✔ %-16s%s %s (%ss)\n' "$C_GREEN" "$step" "$C_RESET" "${STEP_TITLE[$step]}" "$secs" ;;
      HATA) printf '  %s✘ %-16s%s %s\n' "$C_RED" "$step" "$C_RESET" "${STEP_TITLE[$step]}"; any_fail=1 ;;
      ATLA) printf '  - %-16s %s (atlandı)\n' "$step" "${STEP_TITLE[$step]}" ;;
    esac
  done

  if [[ -s $NOTES_FILE ]]; then
    printf '\n%sNotlar:%s\n' "$C_BOLD" "$C_RESET"
    sed 's/^/  • /' "$NOTES_FILE"
  fi

  printf '\n  Günlük dosyası: %s\n' "$LOG_FILE"
  if (( any_fail )); then
    printf '\n%sBazı adımlar başarısız oldu.%s Sorunu giderip sadece o adımı tekrar çalıştırabilirsiniz:\n' "$C_YELLOW" "$C_RESET"
    printf '  ./install.sh --only ADIM_ADI\n'
  fi
  if [[ -f $STATE_DIR/reboot ]]; then
    printf '\n%s%sKurulumun tamamlanması için bilgisayarı yeniden başlatın:  sudo reboot%s\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
  fi
  return "$any_fail"
}

main() {
  if [[ -z ${UBUNTU_STARTER_DETACHED:-} ]] && ! is_on "$FOREGROUND" \
     && has_systemd && command -v systemd-run >/dev/null 2>&1; then
    detach_to_service   # geri dönmez
  fi

  setup_logging
  printf '%subuntu-starter-script v%s%s — %s\n' "$C_BOLD" "$SCRIPT_VERSION" "$C_RESET" "$(date '+%Y-%m-%d %H:%M')"
  preflight
  repair_package_state

  local step
  for step in "${ALL_STEPS[@]}"; do
    if step_selected "$step"; then
      run_step "$step"
    else
      RESULTS+=("ATLA|$step|0")
    fi
  done

  print_summary
}

main
