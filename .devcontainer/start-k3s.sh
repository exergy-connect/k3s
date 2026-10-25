#!/bin/sh
# Start one k3s server for the DCP scavenger demo.
# Leaves about 2 CPUs and 5GiB schedulable on large hosts so extra worker
# slices stay Pending and a 1 CPU task has to preempt them.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

log=/var/log/k3s-devcontainer.log
target_cpu=2
target_mem_kib=$((5 * 1024 * 1024))

if ! [ -e /dev/kmsg ]; then
    mknod /dev/kmsg c 1 11 2>/dev/null || true
fi
modprobe overlay 2>/dev/null || true
modprobe br_netfilter 2>/dev/null || true

# cgroup v2: a container root that both holds processes and enables controllers
# is an invalid domain. Move those processes aside so kubelet can create kubepods.
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    mkdir -p /sys/fs/cgroup/init
    while read -r pid; do
        echo "$pid" >/sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done </sys/fs/cgroup/cgroup.procs
    sed -e 's/ / +/g' -e 's/^/+/' /sys/fs/cgroup/cgroup.controllers >/sys/fs/cgroup/cgroup.subtree_control
fi

started=0
if ! pgrep -x k3s >/dev/null 2>&1; then
    started=1
    cpus=$(nproc)
    mem_kib=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    reserve_cpu=0
    reserve_mem_kib=0
    if [ "$cpus" -gt "$target_cpu" ]; then
        reserve_cpu=$((cpus - target_cpu))
    fi
    if [ "$mem_kib" -gt "$target_mem_kib" ]; then
        reserve_mem_kib=$((mem_kib - target_mem_kib))
    fi

    set -- server \
        --write-kubeconfig-mode 644 \
        --disable=traefik \
        --disable=servicelb \
        --snapshotter=native \
        --tls-san=127.0.0.1

    reserved=""
    if [ "$reserve_cpu" -gt 0 ]; then
        reserved="cpu=${reserve_cpu}"
    fi
    if [ "$reserve_mem_kib" -gt 0 ]; then
        if [ -n "$reserved" ]; then
            reserved="${reserved},memory=${reserve_mem_kib}Ki"
        else
            reserved="memory=${reserve_mem_kib}Ki"
        fi
    fi
    if [ -n "$reserved" ]; then
        set -- "$@" --kubelet-arg="system-reserved=${reserved}"
    fi

    echo "starting k3s: k3s $*"
    # Detach from the postStart session so k3s keeps running.
    setsid k3s "$@" >>"$log" 2>&1 </dev/null &
fi

i=0
while [ "$i" -lt 90 ]; do
    if [ "$started" -eq 1 ] && [ "$i" -gt 2 ] && ! pgrep -x k3s >/dev/null 2>&1; then
        echo "k3s exited before the node was Ready" >&2
        tail -n 80 "$log" >&2 || true
        exit 1
    fi
    if k3s kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" { found = 1 } END { exit !found }'; then
        echo "k3s is Ready. Schedulable capacity:"
        k3s kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory
        echo "Demo: cd contrib/dcp-scavenger && kubectl apply -f scavenger.yaml"
        if [ "$(uname -m)" != "x86_64" ]; then
            echo "warning: distributivenetwork/dcp-worker is published for linux/amd64; this node is $(uname -m)" >&2
        fi
        exit 0
    fi
    i=$((i + 1))
    sleep 2
done

echo "k3s did not become Ready within 180s" >&2
tail -n 80 "$log" >&2 || true
exit 1
