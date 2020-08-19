#!/bin/bash

set -euxo pipefail

captest --text
mount

mkdir /etc/nomad
cat >/etc/nomad/local.hcl <<'_END_'
bind_addr = "0.0.0.0"
data_dir  = "/var/lib/nomad"
client {
    options = {
        "docker.volumes.enabled" = true
    }
}
_END_

# strace -o /host/nomad.strace -f -s300
exec /nomad agent -config /etc/nomad -dev
