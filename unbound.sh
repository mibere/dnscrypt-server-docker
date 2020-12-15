#! /usr/bin/env bash

function waitForRedis {
    maxTries=15
    try=1
    alive=""
    sleep 3s
    while [ $try -le $maxTries ]; do
        sleep 2s
        alive=$(redis-cli -p 5769 ping | grep -i PONG)
        if [ -n "$alive" ]; then return; fi
        try=$(( try + 1 ))
    done
    echo "Redis is not running" >&2
    exit 1
}

function restartRedis {
    waitForRedis
    service redis-server stop
    sleep 2s
    service redis-server start
    waitForRedis
}

function startRedis {
    service redis-server start
    waitForRedis
}

KEYS_DIR="/opt/encrypted-dns/etc/keys"
ZONES_DIR="/opt/unbound/etc/unbound/zones"

availableMemInMB=$(( $( (grep -F MemAvailable /proc/meminfo || grep -F MemTotal /proc/meminfo) | sed 's/[^0-9]//g' ) / 1024 ))
if [ $availableMemInMB -lt 3000 ]; then
    echo "Not enough available memory" >&2
    exit 1
fi
# msg_cache_size = rr_cache_size / 1.2
rr_cache_size=768
msg_cache_size=640

nproc=$(nproc)
if [ "$nproc" -ge 4 ]; then
    # reserve 2 units (host / operating system, Docker, encrypted-dns)
    punits=$((nproc - 2))

    # don't use more than 8
    if [ "$punits" -gt 8 ]; then punits=8; fi

    # threads used by Unbound
    if [ "$punits" -ge 5 ]; then
        unboundthreads=$((punits - 2))
    else
        unboundthreads=$((punits - 1))
    fi
    export unboundthreads

    # calculate base 2 log of the number of unboundthreads
    unboundthreads_log=$(perl -e 'printf "%5.5f\n", log($ENV{unboundthreads})/log(2);')

    # round the logarithm to an integer
    rounded_unboundthreads_log="$(printf '%.*f\n' 0 "$unboundthreads_log")"

    # set *-slabs to a power of 2 close to the num-threads value 
    slabs=$((2 ** rounded_unboundthreads_log))

    # *-slabs must be at least 4
    if [ "$slabs" -lt 4 ]; then slabs=4; fi

    # *-slabs must not be smaller than unboundthreads
    # (every thread should get a slab, without waiting for a free one)
    if [ "$slabs" -lt "$unboundthreads" ]; then slabs=$((slabs * 2)); fi
else
    echo "Not enough processing units" >&2
    exit 1
fi

provider_name=$(cat "$KEYS_DIR/provider_name")

sed \
    -e "s/@PROVIDER_NAME@/${provider_name}/" \
    -e "s/@RR_CACHE_SIZE@/${rr_cache_size}/" \
    -e "s/@MSG_CACHE_SIZE@/${msg_cache_size}/" \
    -e "s/@THREADS@/${unboundthreads}/" \
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
  msg-cache-size: @MSG_CACHE_SIZE@m
  rrset-cache-size: @RR_CACHE_SIZE@m
  neg-cache-size: 16M
  serve-expired: yes
  serve-expired-ttl: 21600
  access-control: 0.0.0.0/0 allow
  access-control: ::0/0 allow
  tls-cert-bundle: "/etc/ssl/certs/ca-certificates.crt"
  aggressive-nsec: yes
  cache-max-negative-ttl: 1800
  extended-statistics: yes
  incoming-num-tcp: 25
  outgoing-num-tcp: 25
  infra-cache-numhosts: 100000
  key-cache-size: 64m
  unwanted-reply-threshold: 100000
  module-config: "validator cachedb iterator"
  root-hints: "var/root.hints"
  msg-cache-slabs: @SLABS@
  rrset-cache-slabs: @SLABS@
  infra-cache-slabs: @SLABS@
  key-cache-slabs: @SLABS@
  log-local-actions: no
  log-replies: no
  log-servfail: no
  log-time-ascii: yes
  val-clean-additional: yes
  val-log-level: 0
  so-rcvbuf: 2m
  so-sndbuf: 2m
  use-syslog: no
  logfile: "var/unbound.log"
  udp-connect: no
  do-ip4: yes
  do-ip6: no
  prefer-ip4: yes
  prefer-ip6: no
  val-bogus-ttl: 300

  # https://blog.cloudflare.com/rfc8482-saying-goodbye-to-any/
  deny-any: yes

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

  # https://support.mozilla.org/en-US/kb/canary-domain-use-application-dnsnet
  local-zone: "use-application-dns.net." always_nxdomain

  include: "@ZONES_DIR@/*.conf"

cachedb:
  backend: "redis"
  redis-server-host: 127.0.0.1
  redis-server-port: 5769
  redis-expire-records: no
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
    curl -sSf --connect-timeout 15 --retry 2 --retry-delay 10 --max-time 60 https://www.internic.net/domain/named.root -o /opt/unbound/etc/unbound/var/root.hints &&
    /opt/unbound/sbin/unbound-anchor -r /opt/unbound/etc/unbound/var/root.hints -a /opt/unbound/etc/unbound/var/root.key

if [ ! -f /opt/unbound/etc/unbound/unbound_control.pem ]; then
    /opt/unbound/sbin/unbound-control-setup 2> /dev/null || :
fi

mkdir -p /opt/unbound/etc/unbound/zones
mkdir -p /var/lib/redis && chown -R redis:redis /var/lib/redis

# threads used by Redis, default 1
if [ "$punits" -ge 6 ]; then
    sed -i 's/^io-threads 1$/io-threads 2/g' /etc/redis/redis.conf
fi
startRedis

exec /opt/unbound/sbin/unbound -c /opt/unbound/etc/unbound/unbound.conf
