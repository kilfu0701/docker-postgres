FROM debian:bullseye-20220328-slim
MAINTAINER BoRu Su <kilfu0701@gmail.com>

# define VERSION
ENV PG_MAJOR 14
ENV PG_VERSION 14.2
ENV PG_SHA256 2cf78b2e468912f8101d695db5340cf313c2e9f68a612fb71427524e8c9a977a
#ENV PG_BLOCKSIZE 32
#ENV PG_WAL_BLOCKSIZE 64

# add postgres user and group
RUN set -eux; \
    groupadd postgres; \
    useradd -g postgres postgres; \
    mkdir -p /var/lib/postgresql; \
    chown -R postgres:postgres /var/lib/postgresql

# update yum & install packages
RUN set -eux; \
    apt update -y; \
    apt install -y build-essential wget vim tzdata zstd gosu procps

# install dependencies libs for compile
RUN set -eux; \
    apt install -y llvm \
        llvm-dev \
        clang g++ \
        pkg-config \
        libicu-dev \
        liblz4-dev \
        zlib1g-dev \
        python3-dev \
        libreadline-dev \
        libssl-dev \
        libxml2-dev \
        libxslt-dev \
        libedit-dev \
        libkrb5-dev \
        libldap-dev \
        uuid-dev \
        tcl \
        tcl-dev \
        libperl-dev \
        pax-utils;

# instal needed perl modules
RUN cpan Data::Dumper Error Git TermReadKey Test::Harness Thread::Queue XML::Parser srpm::macros IPC::Run

# download source and compile
RUN set -eux; \
    \
    wget -O postgresql.tar.bz2 "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2"; \
    echo "$PG_SHA256 *postgresql.tar.bz2" | sha256sum -c -; \
    mkdir -p /usr/src/postgresql; \
    tar \
        --extract \
        --file postgresql.tar.bz2 \
        --directory /usr/src/postgresql \
        --strip-components 1 \
    ; \
    rm postgresql.tar.bz2; \
    \
    cd /usr/src/postgresql; \
# update "DEFAULT_PGSOCKET_DIR" to "/var/run/postgresql" (matching Debian)
# see https://anonscm.debian.org/git/pkg-postgresql/postgresql.git/tree/debian/patches/51-default-sockets-in-var.patch?id=8b539fcb3e093a521c095e70bdfa76887217b89f
    awk '$1 == "#define" && $2 == "DEFAULT_PGSOCKET_DIR" && $3 == "\"/tmp\"" { $3 = "\"/var/run/postgresql\""; print; next } { print }' src/include/pg_config_manual.h > src/include/pg_config_manual.h.new; \
    grep '/var/run/postgresql' src/include/pg_config_manual.h.new; \
    mv src/include/pg_config_manual.h.new src/include/pg_config_manual.h; \
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
# explicitly update autoconf config.guess and config.sub so they support more arches/libcs
    wget -O config/config.guess 'https://git.savannah.gnu.org/cgit/config.git/plain/config.guess?id=7d3d27baf8107b630586c962c057e22149653deb'; \
    wget -O config/config.sub 'https://git.savannah.gnu.org/cgit/config.git/plain/config.sub?id=7d3d27baf8107b630586c962c057e22149653deb'; \
# configure options taken from:
# https://anonscm.debian.org/cgit/pkg-postgresql/postgresql.git/tree/debian/rules?h=9.5
    ./configure \
        --build=$gnuArch \
        --enable-integer-datetimes \
        --enable-thread-safety \
        --enable-tap-tests \
        --disable-rpath \
        --with-uuid=e2fs \
        --with-gnu-ld \
        --with-pgport=5432 \
        --with-system-tzdata=/usr/share/zoneinfo \
        --prefix=/usr/local \
        --with-includes=/usr/local/include \
        --with-libraries=/usr/local/lib \
        --with-krb5 \
        --with-gssapi \
        --with-ldap \
        --with-tcl \
        --with-perl \
        --with-python \
        --with-openssl \
        --with-libxml \
        --with-libxslt \
        --with-icu \
        --with-llvm \
        --with-lz4 \
        #--with-blocksize=$PG_BLOCKSIZE \
        #--with-wal-blocksize=$PG_WAL_BLOCKSIZE \
    ; \
    make -j "$(nproc)" world; \
    make install-world; \
    make -C contrib install; \
    \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
# Remove plperl, plpython and pltcl dependencies by default to save image size
# To use the pl extensions, those have to be installed in a derived image
            | grep -v -e perl -e python -e tcl \
    )"; \
    cd /; \
    rm -rf \
        /usr/src/postgresql \
        /usr/local/share/doc \
        /usr/local/share/man \
    ; \
    \
    postgres --version

# make the sample config easier to munge (and "correct by default")
RUN set -eux; \
	cp -v /usr/local/share/postgresql/postgresql.conf.sample /usr/local/share/postgresql/postgresql.conf.sample.orig; \
	sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/local/share/postgresql/postgresql.conf.sample; \
	grep -F "listen_addresses = '*'" /usr/local/share/postgresql/postgresql.conf.sample

RUN mkdir -p /var/run/postgresql && chown -R postgres:postgres /var/run/postgresql && chmod 2777 /var/run/postgresql

RUN mkdir /docker-entrypoint-initdb.d

ENV PGDATA /var/lib/postgresql/data

# this 777 will be replaced by 700 at runtime (allows semi-arbitrary "--user" values)
RUN mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA" && chmod 777 "$PGDATA"
VOLUME /var/lib/postgresql/data

ENV LD_LIBRARY_PATH /usr/local/lib

ADD entrypoint.sh /entrypoint.sh
RUN chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

ADD conf/postgresql.conf /var/lib/postgresql/data/postgresql.conf

STOPSIGNAL SIGINT
EXPOSE 5432
CMD ["postgres"]
