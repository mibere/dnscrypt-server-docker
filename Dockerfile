FROM ubuntu:20.10
LABEL maintainer="dnscrypt.one / mibere"
LABEL origin="Frank Denis"
SHELL ["/bin/sh", "-x", "-c"]

ARG RUNTIME_DEPS="bash util-linux coreutils tzdata findutils grep runit runit-helper libssl1.1 ca-certificates curl ldnsutils libevent-2.1 expat nano libhiredis0.1 redis-server"
ARG BUILD_DEPS="make build-essential git libevent-dev libexpat1-dev autoconf file libssl-dev byacc libhiredis-dev"

ARG CFLAGS="-O2"
# Get rid of the warning "debconf: falling back to frontend" during build time:
ARG DEBIAN_FRONTEND="noninteractive"

# Timezone
ENV TZ="Etc/UTC"

# First install 'apt-utils' to get rid of the warning "debconf: delaying
# package configuration, since apt-utils is not installed" during build time 
RUN apt-get update && \
    apt-get install -qy --no-install-recommends apt-utils && \
    apt-get -qy dist-upgrade && \
    apt-get install -qy --no-install-recommends $RUNTIME_DEPS && \
    apt-get -qy clean && \
    rm -fr /tmp/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/* /var/log/apt/* /var/log/*.log

# Set timezone
RUN echo $TZ > /etc/timezone && \
    rm /etc/localtime && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

RUN update-ca-certificates 2> /dev/null || true

WORKDIR /tmp

ARG UNBOUND_GIT_URL="https://github.com/NLnetLabs/unbound.git"
ARG UNBOUND_GIT_REVISION="release-1.13.1"

RUN apt-get update && apt-get install -qy --no-install-recommends $BUILD_DEPS && \
    git clone "$UNBOUND_GIT_URL" && \
    cd unbound && \
    git checkout "$UNBOUND_GIT_REVISION" && \
    groupadd _unbound && \
    useradd -g _unbound -s /usr/sbin/nologin -d /dev/null _unbound && \
    ./configure --prefix=/opt/unbound --with-pthreads \
    --with-username=_unbound --with-libevent --with-libhiredis --enable-cachedb && \
    make -j"$(getconf _NPROCESSORS_ONLN)" install && \
    mv /opt/unbound/etc/unbound/unbound.conf /opt/unbound/etc/unbound/unbound.conf.example && \
    apt-get -qy purge $BUILD_DEPS && apt-get -qy autoremove --purge && apt-get -qy clean && \
    rm -fr /opt/unbound/share/man && \
    rm -fr /tmp/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/* /var/log/apt/* /var/log/*.log

ARG RUSTFLAGS="-C link-arg=-s"

RUN apt-get update && apt-get install -qy --no-install-recommends $BUILD_DEPS && \
    curl -sSf https://sh.rustup.rs | bash -s -- -y --default-toolchain stable && \
    export PATH="$HOME/.cargo/bin:$PATH" && \
    cargo install encrypted-dns && \
    mkdir -p /opt/encrypted-dns/sbin && \
    mv ~/.cargo/bin/encrypted-dns /opt/encrypted-dns/sbin/ && \
    strip --strip-all /opt/encrypted-dns/sbin/encrypted-dns && \
    apt-get -qy purge $BUILD_DEPS && apt-get -qy autoremove --purge && apt-get -qy clean && \
    sed -i '/^source "\$HOME\/\.cargo\/env"$/d' ~/.profile && \
    sed -i '/^source "\$HOME\/\.cargo\/env"$/d' ~/.bashrc && \    
    rm -fr ~/.cargo ~/.rustup && \
    rm -fr /tmp/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/* /var/log/apt/* /var/log/*.log

RUN groupadd _encrypted-dns && \
    mkdir -p /opt/encrypted-dns/empty && \
    useradd -g _encrypted-dns -s /usr/sbin/nologin -d /opt/encrypted-dns/empty _encrypted-dns && \
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
