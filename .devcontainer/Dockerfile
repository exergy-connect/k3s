FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    KUBECONFIG=/etc/rancher/k3s/k3s.yaml

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        iproute2 \
        iptables \
        kmod \
        procps \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# Pinned stable release, not a binary built from this checkout. The scavenger
# demo uses stock Kubernetes APIs. This is the self-extracting release binary:
# on first start it unpacks CNI plugins and the other tools it needs.
# kubectl is a symlink; k3s dispatches on argv0.
ARG K3S_VERSION=v1.36.5+k3s1
RUN set -eu \
    && version_url=$(printf '%s' "${K3S_VERSION}" | sed 's/+/%2B/g') \
    && base="https://github.com/k3s-io/k3s/releases/download/${version_url}" \
    && curl -fsSL --retry 5 --retry-delay 2 -o /tmp/sha256sum-amd64.txt "${base}/sha256sum-amd64.txt" \
    && curl -fL --retry 5 --retry-all-errors --retry-delay 2 -o /usr/local/bin/k3s "${base}/k3s" \
    && (cd /usr/local/bin && grep ' k3s$' /tmp/sha256sum-amd64.txt | sha256sum -c -) \
    && chmod 755 /usr/local/bin/k3s \
    && ln -sf k3s /usr/local/bin/kubectl \
    && ln -sf k3s /usr/local/bin/crictl \
    && ln -sf k3s /usr/local/bin/ctr \
    && rm -f /tmp/sha256sum-amd64.txt

COPY start-k3s.sh /usr/local/bin/start-k3s.sh
RUN chmod 755 /usr/local/bin/start-k3s.sh \
    && useradd --create-home --shell /bin/bash vscode \
    && echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
    && chmod 440 /etc/sudoers.d/vscode

USER vscode
WORKDIR /workspaces/k3s
