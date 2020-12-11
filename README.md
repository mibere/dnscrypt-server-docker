Fork of [DNSCrypt/dnscrypt-server-docker](https://github.com/DNSCrypt/dnscrypt-server-docker) with Redis and modified configuration.

Docker image used by https://dnscrypt.one

###### System requirements

- 4 or more processing units (reported by _nproc_)
- 3 GB free RAM
- Debian 10 (Buster)
- Docker 19.03.13

###### Preparations

_/etc/sysctl.conf_
```
fs.file-max = 524288

net.core.rmem_default = 4194304
net.core.rmem_max = 4194304
net.core.wmem_default = 4194304
net.core.wmem_max = 4194304

net.core.somaxconn = 4096
net.core.optmem_max = 65536
net.core.netdev_max_backlog = 16384
net.ipv4.ip_local_port_range = 24576 60999
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0

vm.overcommit_memory = 1
```
```
sysctl -p
```

_/etc/security/limits.conf_
```
root    soft    nofile  75000
root    hard    nofile  75000
*       soft    nofile  75000
*       hard    nofile  75000
```

[Disabled Transparent Huge Pages](https://redis.io/topics/latency), _/lib/systemd/system/redis-dthp.service_

```
[Unit]
Description=Disable transparent huge pages
Documentation=https://redis.io/topics/latency
Before=containerd.service docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/sh -c "/usr/bin/echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled"
#ExecStart=/usr/bin/sh -c "/usr/bin/echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag"

[Install]
WantedBy=multi-user.target
```

```
systemctl daemon-reload
systemctl enable redis-dthp.service
mkdir -p /etc/dnscrypt-server/keys
mkdir /etc/dnscrypt-server/redis
shutdown -r now
```

###### Start container

Adjust _NAME_ and _IP:PORT_

```
docker run --name=dnscrypt-server --net=host --restart=unless-stopped -v /etc/dnscrypt-server/keys:/opt/encrypted-dns/etc/keys -v /etc/dnscrypt-server/redis:/var/lib/redis mibere/dnscrypt-server init -N NAME -A -E 'IP:PORT'
```
