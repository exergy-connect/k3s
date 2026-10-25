# DCP scavenger workers

Run [Distributive Docker Workers](https://distributive.network/docs/worker-docker.html) on CPU and memory that no other pod has requested. When a normal pod needs that capacity, the scheduler preempts only enough worker slices to place it. After the pod exits, pending slices take the slack back.

This uses stock Kubernetes priority and preemption. It is not part of the k3s server. Apply it by hand. Leave it out of `/var/lib/rancher/k3s/server/manifests`, which k3s applies on its own.

Unused capacity here means allocatable CPU and memory with no pod request against it. k3s system reservations stay outside allocatable. A worker does not borrow CPU that another pod has already requested, even if that pod is idle.

## What gets applied

`scavenger.yaml` creates:

- Namespace `dcp-scavenger`.
- PriorityClass `dcp-scavenger` at `-1000` with `preemptionPolicy: Never`. Normal pods are priority 0. k3s system pods use `system-cluster-critical` and `system-node-critical`, which are higher still.
- A Deployment of 16 worker slices. Each slice requests and limits `500m` CPU and `1Gi` memory, so the slice is Guaranteed and kubelet eviction leaves it alone. Preemption can still delete it. `terminationGracePeriodSeconds` is 15, and there is no PodDisruptionBudget.

The image is `distributivenetwork/dcp-worker:latest` (linux/amd64). An unregistered container starts on its own and holds earnings in a temporary account, so this demo needs no DCP key. Args `--cores=1,0` and `--max-sandboxes=1` keep each slice to one CPU sandbox and no GPU. The container entrypoint may start as root so it can drop to the unprivileged `dcp` user; the pod is not privileged and does not use the host network, a host path, or a service-account token.

Replicas are higher than a node can hold. Slices that fit run. The rest stay `Pending`. `topologySpreadConstraints` prefer an even spread across nodes and still allow a larger node to take extra slices.

## Demo

Use one k3s node with at least 2 CPUs and 4GiB of RAM, and outbound HTTPS so a worker can reach the public DCP scheduler. CoreDNS and metrics-server each request `100m` CPU and `70Mi` memory, so a node of that size should still run at least two slices.

1. Start k3s and apply the scavenger:

   ```sh
   kubectl apply -f scavenger.yaml
   kubectl get pods -n dcp-scavenger -w
   ```

   The first start pulls an image of about 500MB. Expect a few pods `Running` and the rest `Pending` with `Insufficient cpu` or `Insufficient memory`.

2. Confirm the node requests are near allocatable:

   ```sh
   kubectl describe node
   ```

3. Confirm a worker joined the public scheduler. This checks the image and the network. Preemption does not depend on it:

   ```sh
   kubectl logs -n dcp-scavenger -l app=dcp-worker --tail=50
   ```

4. Admit a stand-in task that requests `1` CPU and `1Gi` memory. That is two slices:

   ```sh
   kubectl apply -f task.yaml
   kubectl get pods -n dcp-scavenger -w
   ```

   Within the 15 second grace period, enough `dcp-worker` pods go `Terminating` for `scavenger-task` to become `Running`. Other workers stay up. If the node only had one slice running, edit `task.yaml` so the pause container requests `cpu: 500m` and `memory: 1Gi`, then apply it again. That preempts a single slice.

5. Give the capacity back:

   ```sh
   kubectl delete -f task.yaml
   kubectl get pods -n dcp-scavenger -w
   ```

   Pending workers become `Running` and the node fills back up.

6. Remove the demo:

   ```sh
   kubectl delete -f scavenger.yaml
   ```

Success is steps 4 and 5. Credit in the DCP portal appears only after the worker is registered.

## After the demo

To deposit earnings, pass `--earnings-account` with the public address from the [DCP portal](https://dcp.cloud). To stay off the public group, pass `--join` and `--no-global`. Pin `distributivenetwork/dcp-worker` to a digest before using this on a shared cluster. Raise the memory limit if a slice is OOMKilled; the worker process and one sandbox share the `1Gi` limit.
