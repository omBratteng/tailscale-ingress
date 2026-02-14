FROM ghcr.io/tailscale/tailscale:v1.94.2 AS builder

ADD https://github.com/samhocevar/rinetd/releases/download/v0.73/rinetd-0.73.tar.gz /tmp/rinetd-0.73.tar.gz

RUN set -xe \
	&& apk add --no-cache \
		build-base \
		autoconf \
		automake \
	&& tar -xzf /tmp/rinetd-0.73.tar.gz -C /tmp \
	&& cd /tmp/rinetd-0.73 \
	&& ./bootstrap \
	&& ./configure --prefix=/usr \
	&& make -j $(nproc)

FROM ghcr.io/tailscale/tailscale:v1.94.2

COPY --from=builder /tmp/rinetd-0.73/rinetd /usr/sbin/rinetd
COPY ./run.sh /tailscale/run.sh

EXPOSE 80/tcp
EXPOSE 443/tcp

CMD ["/bin/sh", "/tailscale/run.sh"]
