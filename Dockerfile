FROM rust:slim as builder

WORKDIR /usr/src

# Create blank project
RUN USER=root cargo new rust-dockerize

# We want dependencies cached, so copy those first.
COPY ./monitor/Cargo.toml ./monitor/Cargo.lock /usr/src/rust-dockerize/

# Set the working directory
WORKDIR /usr/src/rust-dockerize

## Install target platform (Cross-Compilation) --> Needed for Alpine
RUN rustup target add x86_64-unknown-linux-musl

# This is a dummy build to get the dependencies cached.
RUN cargo build --target x86_64-unknown-linux-musl --release

# Now copy in the rest of the sources
COPY ./monitor/src /usr/src/rust-dockerize/src/

## Touch main.rs to prevent cached release build
RUN touch /usr/src/rust-dockerize/src/main.rs

# This is the actual application build.
RUN cargo build --target x86_64-unknown-linux-musl --release

FROM alpine:3.18 AS runtime

RUN apk add --no-cache ca-certificates
RUN apk add libc6-compat
RUN apk add inotify-tools
RUN apk add --no-cache --upgrade bash
RUN apk add curl
RUN apk add docker
RUN apk add trivy

RUN set -eux; \
	# https://github.com/distribution/distribution/releases
	version='2.8.2'; \
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
	x86_64)  arch='amd64';   sha256='b68ffb849bcdb49639dc91ba97baba6618346f95fedc0fcc94871b31d515d205' ;; \
	aarch64) arch='arm64';   sha256='3d500cf4f7f21ade4bdfef28012aef8e1ec2b221d2d8d36d201d94dda84fa727' ;; \
	armhf)   arch='armv6';   sha256='e65aeccf69e779681f75b488c4e955f9d9b6aa1d7cf961a9307e8b6d40229373' ;; \
	armv7)   arch='armv7';   sha256='045154b2be7a6a3b5d35e14e9afcd29d01813f46ce7ea2ea40958048b621dfd0' ;; \
	ppc64le) arch='ppc64le'; sha256='21f5523bb0815af9b7e41b52824d422679309773a14a841e8e685e1f521c1ee0' ;; \
	s390x)   arch='s390x';   sha256='2ec05870ffa8c47e764e8de08d00dd0748698cf36394e4b3a503a1339b93e251' ;; \
	*) echo >&2 "error: unsupported architecture: $apkArch"; exit 1 ;; \
	esac; \
	wget -O registry.tar.gz "https://github.com/distribution/distribution/releases/download/v${version}/registry_${version}_linux_${arch}.tar.gz"; \
	echo "$sha256 *registry.tar.gz" | sha256sum -c -; \
	tar --extract --verbose --file registry.tar.gz --directory /bin/ registry; \
	rm registry.tar.gz; \
	registry --version

COPY --from=builder /usr/src/rust-dockerize/target/x86_64-unknown-linux-musl/release/monitor /bin/

COPY ./config-example.yml /etc/docker/registry/config.yml

VOLUME ["/var/lib/registry"]
EXPOSE 5000

COPY docker-entrypoint.sh /entrypoint.sh
COPY action.sh /home/action.sh
COPY cleanup.sh /home/cleanup.sh

RUN chmod +x /home/action.sh
RUN chmod +x /home/cleanup.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/etc/docker/registry/config.yml"]
