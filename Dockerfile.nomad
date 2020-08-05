FROM debian:stable-slim

# hadolint ignore=DL3008,DL3009
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip ca-certificates
RUN curl -LO https://releases.hashicorp.com/nomad/0.12.1/nomad_0.12.1_linux_amd64.zip
RUN unzip nomad_*.zip
CMD ["/nomad", "agent", "-dev", "-bind", "0.0.0.0"]
