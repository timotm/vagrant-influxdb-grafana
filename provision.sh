#!/bin/bash

set -euo pipefail

fatal() {
    echo "$*" 1>&2
    exit 1
}

log() {
    echo "$(date "+%T") $*" 1>&2
}

install_prerequisites() {
    log "Installing needed packages"

    apt update
    apt -y upgrade
    apt install -y apt-transport-https software-properties-common curl gpg jq openssl \
        netcat-openbsd avahi-daemon
}

configure_avahi() {
    log "Configuring avahi-daemon"

    sed -e 's/^\(#\)\?allow-interfaces *=.*/allow-interfaces=enp0s8/' \
        -i /etc/avahi/avahi-daemon.conf
}

install_grafana() {
    log "Installing grafana"

    curl -s https://packages.grafana.com/gpg.key | apt-key add -
    echo "deb https://packages.grafana.com/oss/deb stable main" >/etc/apt/sources.list.d/grafana.list
    apt update
    apt install -y grafana
}

install_influxdb() {
    local -r VERSION="$1"

    log "Installing InfluxDB ${VERSION}"

    if ! [ -e "influxdb-${VERSION}_linux_amd64.tar.gz" ]; then
        curl -sO "https://dl.influxdata.com/influxdb/releases/influxdb-${VERSION}_linux_amd64.tar.gz"
    fi
    mkdir -p /opt/influx/bin
    tar --wildcards --strip-components=1 --directory /opt/influx/bin \
        -xzf "influxdb-${VERSION}_linux_amd64.tar.gz" "*/influx*"
    mv ~vagrant/influxdb.service /etc/systemd/system/
    chown root:root /etc/systemd/system/influxdb.service
}

configure_grafana() {
    local -r token="$1"
    local -r cert_file="$2"
    local -r key_file="$3"

    log "Configuring grafana"

    sed -e "s/%GRAFANA_TOKEN%/${token}/" ~vagrant/influxdb-datasource.yaml \
        >/etc/grafana/provisioning/datasources/influxdb-datasource.yaml

    chown root:grafana "${cert_file}" "${key_file}"
    chmod g+r "${cert_file}" "${key_file}"

    sed -e 's/^\(;\)\?protocol *=.*/protocol = https/' \
        -e "s|^\(;\)\?;cert_file *=.*|cert_file = ${cert_file}|" \
        -e "s|^\(;\)\?;cert_key *=.*|cert_key = ${key_file}|" \
        -i /etc/grafana/grafana.ini

    systemctl restart grafana-server.service
}

setup_influxdb() {
    local -r password="$1"

    log "Setting up InfluxDB"

    if [ -e "${HOME}/.influxdbv2/configs" ]; then
        return
    fi

    sudo -u vagrant /opt/influx/bin/influx setup --username admin \
        --password "${password}" --org home --bucket monitoring --force
}

random_string() {
    openssl rand -hex 20
}

create_write_user_get_token() {
    local -r bucket_id="$(sudo -u vagrant /opt/influx/bin/influx bucket list | awk '$2 == "monitoring" {print $1}')"

    log "Creating InfluxDB write user and token"
    sudo -u vagrant /opt/influx/bin/influx user create --name writer --org home --password "$(random_string)" --json 1>&2
    sudo -u vagrant /opt/influx/bin/influx auth create --org home --user writer --write-bucket "${bucket_id}" --json | jq -r '.token'
}

create_grafana_user_get_token() {
    log "Creating InfluxDB grafana user and token"

    sudo -u vagrant /opt/influx/bin/influx user create --name grafana --org home --password "$(random_string)" --json 1>&2
    sudo -u vagrant /opt/influx/bin/influx auth create --org home --user grafana --read-buckets --json | jq -r '.token'
}

start_services() {
    log "Starting system services"

    systemctl daemon-reload
    systemctl enable --now grafana-server.service influxdb.service avahi-daemon.service
}


wait_for_influx() {
    log "Waiting for InfluxDB to start up"

    for _ in $(seq 10); do
        nc -z 127.0.0.1 8086 && break
        sleep 1
    done

    nc -z 127.0.0.1 8086
}

set_hostname() {
    local -r hostname="$1"

    log "Setting hostname to ${hostname}"

    hostnamectl set-hostname "${hostname}"
    systemctl restart avahi-daemon.service
}

create_ssl_cert() {
    local -r hostname="$1"

    log "Creating self-signed SSL certificate for ${hostname}"

local -r config=$(cat <<EOF
[dn]
CN=${hostname}
[req]
distinguished_name = dn
[EXT]
subjectAltName=DNS:${hostname}
keyUsage=digitalSignature
extendedKeyUsage=serverAuth
EOF
)

    openssl req -x509 -days 3650 -out "/etc/grafana/${hostname}".crt \
        -keyout "/etc/grafana/${hostname}".key \
        -newkey rsa:2048 -nodes -sha256 -subj "/CN=${hostname}" \
        -extensions EXT -config <( echo "${config}" )
}

if [ -z "${INFLUXDB_VERSION}" ]; then
    fatal "INFLUXDB_VERSION not set"
fi

install_prerequisites
configure_avahi

set_hostname "monitoring"

install_grafana
install_influxdb "${INFLUXDB_VERSION}"
start_services
wait_for_influx

readonly grafana_admin_password="$(random_string)"
setup_influxdb "${grafana_admin_password}"

readonly write_token="$(create_write_user_get_token)"
readonly grafana_token="$(create_grafana_user_get_token)"

create_ssl_cert "monitoring.local"

configure_grafana "${grafana_token}" "/etc/grafana/monitoring.local.crt" \
    "/etc/grafana/monitoring.local.key"

echo "${write_token}" > ~vagrant/influx-write-token.txt
echo "${grafana_admin_password}" > ~vagrant/grafana-admin-password.txt
