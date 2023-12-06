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

function purge_pkg() {
  # shellcheck disable=SC2086
  apt -y remove $1 || true
  # shellcheck disable=SC2086
  apt -y purge $1 || true
}

CTRL_VERSION='latest'
USER='shieldwall'
USER_ID='2000'
DIR_HOME='/home/shieldwall'
DIR_LIB='/var/lib/shieldwall'
DIR_LOG='/var/log/shieldwall'
DIR_CNF='/etc/shieldwall'

cd '/tmp/'

log 'SETTING DEFAULT LANGUAGE'
export LANG="en_US.UTF-8"
export LANGUAGE="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
update-locale LANG=en_US.UTF-8 || true
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
purge_pkg 'ufw'
purge_pkg 'firewalld*'
purge_pkg 'arptables'
purge_pkg 'ebtables'
purge_pkg 'xtables*'
if ! [ -f '/etc/systemd/system/docker.service.d/override.conf' ]
then
  purge_pkg 'iptables*'
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
DISTRO="$(lsb_release -i -s | tr '[:upper:]' '[:lower:]')"
CODENAME="$(lsb_release -c -s | tr '[:upper:]' '[:lower:]')"
CPU_ARCH="$(uname -i)"
IS_CONTAINER="$(grep -c 'lxc|docker' < '/proc/self/mountinfo' || echo '0')"

if [[ "$CPU_ARCH" == 'unknown' ]] || [[ "$CPU_ARCH" == 'x86_64' ]]
then
  CPU_ARCH='amd64'
fi

function download_latest_github_release_filter() {
  gh_user="$1"
  gh_repo="$2"
  out_file="$3"
  filter="$4"
  filter_exclude="$5"
  url="$(curl -s "https://api.github.com/repos/${gh_user}/${gh_repo}/releases/latest" | grep 'download_url' | grep "linux-${CPU_ARCH}" | grep "$filter" | grep -Ev "$filter_exclude" | head -n 1 | cut -d '"' -f 4)"
  wget -4 "$url" -O "$out_file"
}

function download_latest_github_release() {
  download_latest_github_release_filter "$1" "$2" "$3" '' '$%&'
}

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

mkdir -p "$DIR_LIB" "$DIR_LOG" "$DIR_CNF"
chown "$USER" "$DIR_LIB" "$DIR_CNF"
chown 'root':'adm' "$DIR_LOG"
chmod 750 "$DIR_LIB" "$DIR_CNF" "$DIR_LOG"

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
rm -f '/etc/apt/sources.list'
cp "${DIR_SETUP}/files/apt/sources.list" '/etc/apt/sources.list'
sed -i "s/CODENAME/$CODENAME/g" '/etc/apt/sources.list'
apt update

log 'ADDING FIREWALL BASE CONFIG'
if [[ "$IS_CONTAINER" == "0" ]]
then
  modprobe 'nft_ct'
  modprobe 'nft_log'
  modprobe 'nft_nat'
  modprobe 'nft_redir'
  modprobe 'nft_limit'
  modprobe 'nft_quota'
  modprobe 'nft_connlimit'
  modprobe 'nft_reject'
  mkdir -p '/var/log/ulog'
  touch '/var/log/ulog/syslogemu.log'
else
  apt install ulogd2
  rm '/etc/logrotate.d/ulogd2'
fi

mkdir -p '/etc/nftables.d/' '/etc/systemd/system/nftables.service.d/'
cp "${DIR_SETUP}/files/packet_filter/service_override.conf" '/etc/systemd/system/nftables.service.d/override.conf'
chown "$USER" '/etc/systemd/system/nftables.service.d/override.conf'

cp "${DIR_SETUP}/files/packet_filter/main.conf" '/etc/nftables.conf'
cp "${DIR_SETUP}/files/packet_filter/nftables.conf" '/etc/nftables.d/managed.conf'
if [[ "$IS_CONTAINER" != "0" ]]
then
  sed -i 's/\(log prefix ".*"\)/\1 group 0/' '/etc/nftables.d/managed.conf'
fi

chmod 750 '/etc/nftables.d/'
chmod 640 '/etc/nftables.conf' '/etc/nftables.d/managed.conf'
chown -R "$USER":"$USER" /etc/nftables*
new_service 'nftables'

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
cp "${DIR_SETUP}/files/docker_service_override.conf" '/etc/systemd/system/docker.service.d/override.conf'
chown "$USER" '/etc/systemd/system/docker.service.d/override.conf'
new_service 'docker'

log 'METRIC CONFIG (PROMETHEUS)'

if ! [ -f '/usr/local/bin/prometheus_proxy' ]
then
  download_latest_github_release_filter 'shield-wall-net' 'Prometheus-Proxy' '/tmp/prometheus_proxy.tar.gz' '' 'client'
  tar -xzf '/tmp/prometheus_proxy.tar.gz' -C '/tmp/'
  mv "/tmp/prometheus-proxy-linux-${CPU_ARCH}-CGO0" '/usr/local/bin/prometheus_proxy'
fi

chown "$USER" '/usr/local/bin/prometheus_proxy'

log 'LOGGING CONFIG'
cp "${DIR_SETUP}/files/log/rsyslog.conf" '/etc/rsyslog.d/shieldwall.conf'
cp "${DIR_SETUP}/files/log/logrotate" '/etc/logrotate.d/shieldwall'

# NOTE: logrotate config must be owned by root and not writable by group
chown "$USER" /etc/rsyslog.d/*shieldwall*

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
cp "${DIR_SETUP}/files/log/grafana-agent.yml" '/etc/shieldwall/log_grafana-agent.yml'
if ! [ -f '/etc/shieldwall/log_prometheus_boxes.yml' ]
then
  cp "${DIR_SETUP}/files/log/prometheus_boxes.yml" '/etc/shieldwall/log_prometheus_boxes.yml'
fi

mkdir -p "${DIR_LIB}/log/grafana"
mkdir -p "${DIR_LIB}/log/loki"

chown grafana:grafana "${DIR_LIB}/log/grafana/"
chown loki:loki "${DIR_LIB}/log/loki/"
chown "$USER" /etc/shieldwall/*

new_service 'shieldwall_logserver'

log 'GRAFANA PLUGINS'

declare -A grafana_plugins
# grafana_plugins[grafana-xxx-yyy]='https://....zip'

for plugin_name in "${!grafana_plugins[@]}"
do
  if ! [ -d "${DIR_LIB}/log/grafana/plugins/${plugin_name}" ]
  then
    plugin_url="${grafana_plugins[$plugin_name]}"
    wget -4 "$plugin_url" -O "/tmp/${plugin_name}.zip"
    unzip "/tmp/${plugin_name}.zip" -d "${DIR_LIB}/log/grafana/plugins/"
    chown -R grafana:grafana "${DIR_LIB}/log/grafana/plugins/${plugin_name}"
  fi
done

systemctl restart shieldwall_logserver.service

echo '#########################################'
log 'SETUP FINISHED! Please reboot the system!'

exit 0

}