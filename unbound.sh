#! /usr/bin/env bash

KEYS_DIR="/opt/encrypted-dns/etc/keys"
ZONES_DIR="/opt/unbound/etc/unbound/zones"

reserved=536870912
availableMemory=$((1024 * $( (grep -F MemAvailable /proc/meminfo || grep -F MemTotal /proc/meminfo) | sed 's/[^0-9]//g')))
if [ $availableMemory -le $((reserved * 2)) ]; then
    echo "Not enough memory" >&2
    exit 1
fi
availableMemory=$((availableMemory - reserved))
msg_cache_size=$((availableMemory / 4))
rr_cache_size=$((availableMemory / 3))

nproc=$(nproc)
if [ "$nproc" -ge 4 ]; then
    threads=$((nproc - 2))
    slabs=4
    if [ "$threads" -ge 4 ]; then
        threads=4 
        slabs=8
    fi
else
    echo "Not enough processing units" >&2
    exit 1
fi

provider_name=$(cat "$KEYS_DIR/provider_name")

sed \
    -e "s/@MSG_CACHE_SIZE@/${msg_cache_size}/" \
    -e "s/@PROVIDER_NAME@/${provider_name}/" \
    -e "s/@RR_CACHE_SIZE@/${rr_cache_size}/" \
    -e "s/@THREADS@/${threads}/" \
    -e "s/@SLABS@/${slabs}/" \
    -e "s#@ZONES_DIR@#${ZONES_DIR}#" \
    > /opt/unbound/etc/unbound/unbound.conf << EOT
server:
  verbosity: 1
  num-threads: @THREADS@
  interface: 127.0.0.1@553
  so-reuseport: yes
  edns-buffer-size: 1232
  delay-close: 10000
  cache-min-ttl: 900
  cache-max-ttl: 86400
  do-daemonize: no
  username: "_unbound"
  log-queries: no
  hide-version: yes
  identity: "DNSCrypt"
  harden-short-bufsize: yes
  harden-large-queries: yes
  harden-glue: yes
  harden-dnssec-stripped: yes
  harden-below-nxdomain: yes
  harden-referral-path: no
  do-not-query-localhost: no
  prefetch: yes
  prefetch-key: yes
  qname-minimisation: yes
  rrset-roundrobin: yes
  minimal-responses: yes
  chroot: "/opt/unbound/etc/unbound"
  directory: "/opt/unbound/etc/unbound"
  auto-trust-anchor-file: "var/root.key"
  num-queries-per-thread: 4096
  outgoing-range: 8192
  msg-cache-size: @MSG_CACHE_SIZE@
  rrset-cache-size: @RR_CACHE_SIZE@
  neg-cache-size: 16M
  serve-expired: yes
  serve-expired-ttl: 21600
  access-control: 0.0.0.0/0 allow
  access-control: ::0/0 allow
  tls-cert-bundle: "/etc/ssl/certs/ca-certificates.crt"
  aggressive-nsec: yes
  cache-max-negative-ttl: 1800
  extended-statistics: yes
  incoming-num-tcp: 20
  outgoing-num-tcp: 20
  infra-cache-numhosts: 50000
  key-cache-size: 64m
  unwanted-reply-threshold: 100000
  module-config: "validator cachedb iterator"
  root-hints: "var/root.hints"
  msg-cache-slabs: @SLABS@
  rrset-cache-slabs: @SLABS@
  infra-cache-slabs: @SLABS@
  key-cache-slabs: @SLABS@

  local-zone: "1." static
  local-zone: "10.in-addr.arpa." static
  local-zone: "127.in-addr.arpa." static
  local-zone: "16.172.in-addr.arpa." static
  local-zone: "168.192.in-addr.arpa." static
  local-zone: "f.f.ip6.arpa." static
  local-zone: "8.e.f.ip6.arpa." static
  local-zone: "airdream." static
  local-zone: "api." static
  local-zone: "bbrouter." static
  local-zone: "belkin." static
  local-zone: "blinkap." static
  local-zone: "corp." static
  local-zone: "davolink." static
  local-zone: "dearmyrouter." static
  local-zone: "dhcp." static
  local-zone: "dlink." static
  local-zone: "domain." static
  local-zone: "envoy." static
  local-zone: "example." static
  local-zone: "grp." static
  local-zone: "gw==." static
  local-zone: "home." static
  local-zone: "hub." static
  local-zone: "internal." static
  local-zone: "intra." static
  local-zone: "intranet." static
  local-zone: "invalid." static
  local-zone: "ksyun." static
  local-zone: "lan." static
  local-zone: "loc." static
  local-zone: "local." static
  local-zone: "localdomain." static
  local-zone: "localhost." static
  local-zone: "localnet." static
  local-zone: "modem." static
  local-zone: "mynet." static
  local-zone: "myrouter." static
  local-zone: "novalocal." static
  local-zone: "onion." static
  local-zone: "openstacklocal." static
  local-zone: "priv." static
  local-zone: "private." static
  local-zone: "prv." static
  local-zone: "router." static
  local-zone: "telus." static
  local-zone: "test." static
  local-zone: "totolink." static
  local-zone: "wlan_ap." static
  local-zone: "workgroup." static
  local-zone: "zghjccbob3n0." static
  local-zone: "@PROVIDER_NAME@." refuse

  include: "@ZONES_DIR@/*.conf"

cachedb:
  backend: "redis"
  redis-server-host: 127.0.0.1
  redis-server-port: 6379
  redis-expire-records: yes
  secret-seed: "Unbound"

remote-control:
  control-enable: yes
  control-interface: 127.0.0.1

auth-zone:
  name: "."
  url: "https://www.internic.net/domain/root.zone"
  fallback-enabled: yes
  for-downstream: no
  for-upstream: yes
  zonefile: "var/root.zone"
EOT

mkdir -p /opt/unbound/etc/unbound/dev &&
    cp -a /dev/random /dev/urandom /opt/unbound/etc/unbound/dev/

mkdir -p -m 700 /opt/unbound/etc/unbound/var &&
    chown _unbound:_unbound /opt/unbound/etc/unbound/var &&
    curl -sSf --connect-timeout 10 --max-time 60 https://www.internic.net/domain/named.root -o /opt/unbound/etc/unbound/var/root.hints &&
    /opt/unbound/sbin/unbound-anchor -r /opt/unbound/etc/unbound/var/root.hints -a /opt/unbound/etc/unbound/var/root.key

if [ ! -f /opt/unbound/etc/unbound/unbound_control.pem ]; then
    /opt/unbound/sbin/unbound-control-setup 2> /dev/null || :
fi

mkdir -p /opt/unbound/etc/unbound/zones

mkdir -p /var/lib/redis &&
    chown -R redis:redis /var/lib/redis &&
    service redis-server start

exec /opt/unbound/sbin/unbound
