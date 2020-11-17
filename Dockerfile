FROM ubuntu:20.04
LABEL maintainer="dnscrypt.one / mibere"
LABEL origin="Frank Denis"
SHELL ["/bin/sh", "-x", "-c"]
ENV SERIAL 1

ENV CFLAGS=-Ofast
ENV BUILD_DEPS   make build-essential git libevent-dev libexpat1-dev autoconf file libssl-dev byacc libhiredis-dev
ENV RUNTIME_DEPS bash util-linux coreutils findutils grep runit runit-helper cron logrotate libssl1.1 ca-certificates curl dialog whiptail readline-common ldnsutils libevent-2.1 expat nano redis-server

RUN apt-get update && apt-get -qy dist-upgrade && \
    apt-get install -qy --no-install-recommends $RUNTIME_DEPS && \
    apt-get -qy clean && \
    rm -fr /tmp/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/* /var/log/apt/* /var/log/*.log

RUN update-ca-certificates 2> /dev/null || true

ENV UNBOUND_GIT_URL https://github.com/NLnetLabs/unbound.git
ENV UNBOUND_GIT_REVISION release-1.12.0

WORKDIR /tmp

RUN apt-get update && apt-get install -qy --no-install-recommends $BUILD_DEPS && \
    git clone --depth=1000 "$UNBOUND_GIT_URL" && \
    cd unbound && \
    git checkout "$UNBOUND_GIT_REVISION" && \
    groupadd _unbound && \
    useradd -g _unbound -s /etc -d /dev/null _unbound && \
    ./configure --prefix=/opt/unbound --with-pthreads \
    --with-username=_unbound --with-libevent --with-libhiredis --enable-cachedb && \
    make -j"$(getconf _NPROCESSORS_ONLN)" install && \
    mv /opt/unbound/etc/unbound/unbound.conf /opt/unbound/etc/unbound/unbound.conf.example && \
    apt-get -qy purge $BUILD_DEPS && apt-get -qy autoremove --purge && apt-get -qy clean && \
    rm -fr /opt/unbound/share/man && \
    rm -fr /tmp/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/* /var/log/apt/* /var/log/*.log

ENV RUSTFLAGS "-C link-arg=-s"

RUN apt-get update && apt-get install -qy --no-install-recommends $BUILD_DEPS && \
    curl -sSf https://sh.rustup.rs | bash -s -- -y --default-toolchain stable && \
    export PATH="$HOME/.cargo/bin:$PATH" && \
    echo "Compiling encrypted-dns" && \
    cargo install encrypted-dns && \
    mkdir -p /opt/encrypted-dns/sbin && \
    mv ~/.cargo/bin/encrypted-dns /opt/encrypted-dns/sbin/ && \
    strip --strip-all /opt/encrypted-dns/sbin/encrypted-dns && \
    apt-get -qy purge $BUILD_DEPS && apt-get -qy autoremove --purge && apt-get -qy clean && \
    rm -fr ~/.cargo ~/.rustup && \
    rm -fr /tmp/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/* /var/log/apt/* /var/log/*.log

RUN groupadd _encrypted-dns && \
    mkdir -p /opt/encrypted-dns/empty && \
    useradd -g _encrypted-dns -s /etc -d /opt/encrypted-dns/empty _encrypted-dns && \
    mkdir -m 700 -p /opt/encrypted-dns/etc/keys && \
    mkdir -m 700 -p /opt/encrypted-dns/etc/lists && \
    chown _encrypted-dns:_encrypted-dns /opt/encrypted-dns/etc/keys && \
    mkdir -m 700 -p /opt/dnscrypt-wrapper/etc/keys && \
    mkdir -m 700 -p /opt/dnscrypt-wrapper/etc/lists && \
    chown _encrypted-dns:_encrypted-dns /opt/dnscrypt-wrapper/etc/keys

RUN mkdir -p \
    /etc/service/unbound \
    /etc/service/watchdog

COPY encrypted-dns.toml.in /opt/encrypted-dns/etc/
COPY undelegated.txt /opt/encrypted-dns/etc/
COPY entrypoint.sh /
COPY unbound.sh /etc/service/unbound/run
COPY unbound-check.sh /etc/service/unbound/check
COPY encrypted-dns.sh /etc/service/encrypted-dns/run
COPY watchdog.sh /etc/service/watchdog/run
COPY redis.conf /etc/redis/

VOLUME ["/opt/encrypted-dns/etc/keys"]
VOLUME ["/var/lib/redis"]

EXPOSE 443/udp 443/tcp

CMD ["/entrypoint.sh", "start"]

ENTRYPOINT ["/entrypoint.sh"]
