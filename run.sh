#!/bin/sh

export PATH=$PATH:/tailscale/bin

TS_AUTH_KEY="${TS_AUTH_KEY:-}"
TS_EXTRA_ARGS="${TS_EXTRA_ARGS:-}"
TS_USERSPACE="${TS_USERSPACE:-true}"
TS_STATE_DIR="${TS_STATE_DIR:-}"
TS_ACCEPT_DNS="${TS_ACCEPT_DNS:-false}"
TS_SOCKS5_SERVER="${TS_SOCKS5_SERVER:-}"
TS_TAILSCALED_EXTRA_ARGS="${TS_TAILSCALED_EXTRA_ARGS:-}"
TS_SOCKET="${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"

# set -e

TAILSCALED_ARGS="--socket=${TS_SOCKET}"
TAILSCALED_ARGS="${TAILSCALED_ARGS} --state=mem: --statedir=/tmp"

if [[ "${TS_USERSPACE}" == "true" ]]; then
  TAILSCALED_ARGS="${TAILSCALED_ARGS} --tun=userspace-networking"
else
  if [[ ! -d /dev/net ]]; then
    mkdir -p /dev/net
  fi

  if [[ ! -c /dev/net/tun ]]; then
    mknod /dev/net/tun c 10 200
  fi
fi

if [[ ! -z "${TS_TAILSCALED_EXTRA_ARGS}" ]]; then
  TAILSCALED_ARGS="${TAILSCALED_ARGS} ${TS_TAILSCALED_EXTRA_ARGS}"
fi

handler() {
  echo "Caught SIGINT/SIGTERM, shutting down tailscaled"
  kill -s SIGINT $PID
  wait ${PID}
}

echo "Starting tailscaled"
tailscaled ${TAILSCALED_ARGS} &
PID=$!
trap handler SIGINT SIGTERM

HOSTNAME="${FLY_APP_NAME}-${FLY_REGION}-$(hostname)"
UP_ARGS="--accept-dns=${TS_ACCEPT_DNS} --hostname=${HOSTNAME} --accept-routes"
if [[ ! -z "${TS_AUTH_KEY}" ]]; then
  UP_ARGS="--authkey=${TS_AUTH_KEY} ${UP_ARGS}"
fi
if [[ ! -z "${TS_EXTRA_ARGS}" ]]; then
  UP_ARGS="${UP_ARGS} ${TS_EXTRA_ARGS:-}"
fi

echo "Running tailscale up"
tailscale --socket="${TS_SOCKET}" up ${UP_ARGS}

echo "Waiting for tailscaled to exit"

echo "allow *.*.*.*" > /etc/rinetd.conf
echo "logfile /dev/stdout" >> /etc/rinetd.conf
echo "0.0.0.0  80   ${REDIRECT_TARGET}   80" >> /etc/rinetd.conf
echo "0.0.0.0  443  ${REDIRECT_TARGET}   443" >> /etc/rinetd.conf
echo "0.0.0.0  3000  100.84.107.107   3000" >> /etc/rinetd.conf

rinetd -f -c /etc/rinetd.conf &
wait ${PID}
