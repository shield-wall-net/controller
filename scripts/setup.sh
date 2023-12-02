#!/bin/bash

set -euo pipefail

echo ''
echo '#############################'
echo '### SHIELDWALL CONTROLLER ###'
echo '#############################'
echo ''

if [[ "$(id -u)" != '0' ]]
then
  echo "ERROR: Script needs to be ran as root!"
  exit 1
fi

# shellcheck disable=SC2009
if ! [ -f '/lib/systemd/systemd' ] || ! ps 1 | grep -qE 'systemd|/sbin/init'
then
  echo "ERROR: ShieldWall depends on Systemd! Init process is other!"
  exit 1
fi

function log() {
  echo ''
  echo "### $1 ###"
  echo ''
  sleep 2
}

function new_service() {
  echo "Enabling & starting $1.service ..."
  systemctl daemon-reload
  systemctl enable "$1.service"
  systemctl start "$1.service"
  systemctl restart "$1.service"
}

CTRL_VERSION='latest'
USER='shieldwall'
USER_ID='2000'
DIR_HOME='/home/shieldwall'
DIR_LIB='/var/local/lib/shieldwall'
DIR_SCRIPT='/usr/local/bin/shieldwall'
DIR_LOG='/var/log/shieldwall'
DIR_CNF='/etc/shieldwall'

cd '/tmp/'

log 'SETTING DEFAULT LANGUAGE'
export LANG="en_US.UTF-8"
export LANGUAGE="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
update-locale LANG=en_US.UTF-8
dpkg-reconfigure --frontend=noninteractive locales

log 'INSTALLING TIMESYNC'
apt install systemd-timesyncd
printf '[Time]\nNTP=0.pool.ntp.org 1.pool.ntp.org\n' > '/etc/systemd/timesyncd.conf'
systemctl enable systemd-timesyncd
systemctl start systemd-timesyncd
systemctl restart systemd-timesyncd
sleep 5

log 'INSTALLING DEPENDENCIES & UTILS'
apt update
apt -y --upgrade install openssl python3 wget gpg lsb-release apt-transport-https ca-certificates gnupg curl net-tools dnsutils zip ncdu man

log 'INSTALLING PACKET-FILTER'
apt -y remove ufw firewalld* arptables ebtables xtables*
apt -y purge ufw firewalld* arptables ebtables xtables*
if ! [ -f '/etc/systemd/system/docker.service.d/override.conf' ]
then
  apt -y remove iptables*
  apt -y purge iptables*
fi
apt -y --upgrade install nftables

log 'INSTALLING SYSLOG'
apt -y --upgrade install rsyslog rsyslog-gnutls logrotate

log 'DOWNLOADING SETUP FILES'
DIR_SETUP="/tmp/controller-${CTRL_VERSION}"
rm -rf "$DIR_SETUP"
wget "https://codeload.github.com/shield-wall-net/controller/zip/refs/heads/${CTRL_VERSION}" -O '/tmp/shieldwall_controller.zip'
unzip 'shieldwall_controller.zip'

log 'CREATING SERVICE-USER & DIRECTORIES'
#DISTRO=$(lsb_release -i -s | tr '[:upper:]' '[:lower:]')
CODENAME=$(lsb_release -c -s | tr '[:upper:]' '[:lower:]')
CPU_ARCH=$(uname -i)

if [[ "$CPU_ARCH" == 'unknown' ]] || [[ "$CPU_ARCH" == 'x86_64' ]]
then
  CPU_ARCH='amd64'
fi

if ! grep -q "$USER" < '/etc/passwd'
then
  useradd "$USER" --shell '/bin/bash' --home-dir "$DIR_HOME" --create-home --uid "$USER_ID"
fi
chown -R "$USER":'root' "$DIR_HOME"
chmod 750 "$DIR_HOME"

if ! grep -q 'ssl-cert' < '/etc/group'
then
  groupadd 'ssl-cert'
fi

mkdir -p "$DIR_LIB" "$DIR_SCRIPT" "$DIR_LOG" "$DIR_CNF"
chown "$USER" "$DIR_LIB" "$DIR_CNF"
chown "$USER":"$USER" "$DIR_SCRIPT" "$DIR_LOG"
chmod 750 "$DIR_LIB" "$DIR_SCRIPT" "$DIR_CNF"
chmod 770 "$DIR_LOG"

touch "${DIR_CNF}/update.env"
chown "$USER" "${DIR_CNF}/update.env"

# todo: easy-rsa CA/PKI
# so services don't die until we get the actual certs
if ! [ -f '/etc/ssl/certs/shieldwall.controller.crt' ]
then
  DUMMY_CERT_CN='/C=AT/O=shield-wall.net/CN=ShieldWall Controller Dummy Cert'
  openssl req -x509 -newkey rsa:4096 -keyout '/etc/ssl/private/shieldwall.controller.key' -out '/etc/ssl/certs/shieldwall.controller.crt' -sha256 -days 3650 -nodes -subj "$DUMMY_CERT_CN"
  DUMMY_CA_CN='/C=AT/O=shield-wall.net/CN=ShieldWall Controller Dummy CA'
  openssl req -x509 -newkey rsa:4096 -keyout '/tmp/dummy.txt' -out '/etc/ssl/certs/shieldwall.ca.crt' -sha256 -days 3650 -nodes -subj "$DUMMY_CA_CN"
  shred '/tmp/dummy.txt'
  ln -s '/etc/ssl/certs/shieldwall.ca.crt' '/etc/ssl/certs/shieldwall.trusted_cas.crt'
fi
chown "$USER":'ssl-cert' '/etc/ssl/certs/shieldwall.controller.crt' '/etc/ssl/private/shieldwall.controller.key' '/etc/ssl/certs/shieldwall.ca.crt'
chown "$USER":'ssl-cert' '/etc/ssl/private'
chmod 750 '/etc/ssl/private'
chmod 640 '/etc/ssl/private/shieldwall.controller.key'

log 'UPDATING DEFAULT APT-REPOSITORIES'
rm '/etc/apt/sources.list'
cp "${DIR_SETUP}/files/apt/sources.list" '/etc/apt/sources.list'
sed -i "s/CODENAME/$CODENAME/g" '/etc/apt/sources.list'

log 'INSTALLING DOCKER'
DOCKER_GPG_FILE='/usr/share/keyrings/docker-archive-keyring.gpg'
DOCKER_REPO_FILE='/etc/apt/sources.list.d/docker.list'

if ! [ -f "$DOCKER_GPG_FILE" ]
then
  wget -4 "https://download.docker.com/linux/${DISTRO}/gpg" -O "${DOCKER_GPG_FILE}_armored"
  gpg --dearmor < "${DOCKER_GPG_FILE}_armored" > "$DOCKER_GPG_FILE"
fi

if ! [ -f "$DOCKER_REPO_FILE" ]
then
  docker_repo="deb [arch=${CPU_ARCH} signed-by=${DOCKER_GPG_FILE}] https://download.docker.com/linux/${DISTRO} ${CODENAME} stable"
  echo "$docker_repo" > "$DOCKER_REPO_FILE"
fi

chmod 644 "$DOCKER_GPG_FILE" "$DOCKER_REPO_FILE"
chown "$USER" "$DOCKER_GPG_FILE" "$DOCKER_REPO_FILE"

apt update
apt -y install docker-ce containerd.io docker-compose-plugin

mkdir -p '/etc/systemd/system/docker.service.d/'
cp "${DIR_SETUP}/files/docker.override.conf" '/etc/systemd/system/docker.service.d/override.conf'
chown "$USER" '/etc/systemd/system/docker.service.d/override.conf'
new_service 'docker'

log 'METRIC CONFIG (PROMETHEUS)'

if ! [ -f '/usr/local/bin/prometheus_proxy' ]
then
  wget "https://github.com/shield-wall-net/Prometheus-Proxy/releases/download/${PROM_PROXY_VERSION}/prometheus-proxy-linux-${CPU_ARCH}-CGO0.tar.gz" -O '/tmp/prometheus_proxy.tar.gz'
  tar -xzf '/tmp/prometheus_proxy.tar.gz' -C '/tmp/' --strip-components=1
  mv "/tmp/prometheus-proxy-linux-${CPU_ARCH}-CGO0" '/usr/local/bin/prometheus_proxy'
fi

log 'LOGGING CONFIG'
cp "${DIR_SETUP}/files/log/rsyslog.conf" '/etc/rsyslog.d/shieldwall.conf'
cp "${DIR_SETUP}/files/log/logrotate" '/etc/logrotate.d/shieldwall'

chown "$USER" /etc/rsyslog.d/*shieldwall*
chown "$USER" '/etc/logrotate.d/shieldwall'

new_service 'rsyslog'
systemctl restart logrotate.service

if ! grep -q 'grafana' < '/etc/passwd'
then
  useradd --uid 472 'grafana' --system
fi
if ! grep -q 'loki' < '/etc/passwd'
then
  useradd --uid 10001 'loki'
fi

cp "${DIR_SETUP}/files/log/grafana.ini" '/etc/shieldwall/log_grafana.ini'
cp "${DIR_SETUP}/files/log/grafana.yml" '/etc/shieldwall/log_grafana.yml'
cp "${DIR_SETUP}/files/log/logserver.service" '/etc/systemd/system/shieldwall_logserver.service'
cp "${DIR_SETUP}/files/log/logserver.yml" '/etc/shieldwall/logserver.yml'
cp "${DIR_SETUP}/files/log/loki.yml" '/etc/shieldwall/log_loki.yml'
cp "${DIR_SETUP}/files/log/prometheus.yml" '/etc/shieldwall/log_prometheus.yml'
cp "${DIR_SETUP}/files/log/promtail.yml" '/etc/shieldwall/log_promtail.yml'

mkdir -p '/var/lib/shieldwall/log/grafana'
mkdir -p '/var/lib/shieldwall/log/loki'

chown grafana:grafana '/var/lib/shieldwall/log/grafana/'
chown loki:loki '/var/lib/shieldwall/log/loki/'
chown "$USER" /etc/shieldwall/*

new_service 'shieldwall_logserver'

echo '#########################################'
log 'SETUP FINISHED! Please reboot the system!'

exit 0