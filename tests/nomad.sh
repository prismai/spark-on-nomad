#!/bin/bash

set -euxo pipefail

captest --text
mount

# strace -o /host/nomad.strace -f -s300
/nomad agent -dev -data-dir /var/lib/nomad -bind 0.0.0.0
