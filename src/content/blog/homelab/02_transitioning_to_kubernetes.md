---
title: Why I Moved the Homelab to Kubernetes
date: 2026-08-20
description: The Docker setup didn't fail dramatically. It failed by a thousand hardcoded IP addresses
tags:
  - homelab
  - kubernetes
  - k3s
  - networking
  - pihole
draft: false
projects:
  - homelab
---

To be fair, not one single digital implementations require Kubernetes for 11 containers. Why am I doing this? Why not.


The Docker setup from [the last post](/blog/homelab/01-original-setup/) worked. It ran for weeks. It never dramatically exploded. But, I found that `jellyfin` containers sometimes would crash especially when running `H265/HEVC` playbacks. 

Normally, I would just SSH into `piloma` using [Termius](https://termius.com/index.html) and then restart the containers. As no humans are born a saint, my patience can't handle it anymore.

## What actually went wrong

### Nothing bounded memory

alomalab has 1.5GB of RAM. Here it is right now, and this is the *healthy*
state:

```bash
free -h
```

```
               total        used        free      shared  buff/cache   available
Mem:           1.5Gi       880Mi       137Mi       384Ki       701Mi       676Mi
Swap:          2.0Gi       250Mi       1.8Gi
```


In short, every container is competing with the last remaining available free memory and kernel OOM killer as the tiebreaker. The OOM killer picks by a heuristic score, not by what you care about, so the thing that dies is frequently not the thing that misbehaved.

And when swap gets involved on a Celeron with a spinning-rust-speed SSD, the
machine doesn't crash, it just becomes unusable for a few minutes, which is
harder to diagnose than a crash.

The honest framing: Docker Compose *does* support memory limits. I could have
set them. But limits are only half of it — the other half is a scheduler that
knows how much RAM each machine has left and refuses to place work that won't
fit. Compose has no concept of that, because Compose has no concept of the
other machine.

### `restart: unless-stopped` is not high availability

Every compose file had `restart: unless-stopped`, which I had quietly filed
under "self-healing". It isn't. It restarts a container on the same host when
the process exits. That covers exactly one failure mode: the process crashed.

It does nothing for:

- the host rebooting after a power blip (fine, actually — it does cover this)
- the host being *off*
- the process being alive but wedged and answering nothing
- the disk filling up
- me closing the laptop lid

There's no health check driving restarts, no notion of "ready" versus
"running", and no possibility of "this workload can't run here, run it
somewhere else", because there is no *somewhere else* in Compose's world.

### Two machines, two sources of truth

It's convenient that Portainer lets me view both hosts container.
But, the state still lived in a dozen YAML files
across two filesystems, edited in place over SSH, with no history.

I could not answer basic questions:

- What changed between "this worked" and "this doesn't"? (No idea, I edited it
  over SSH.)
- What is supposed to be running right now? (Whatever is running, I suppose.)
- If piloma's SD card dies, what do I rebuild? (Reconstruct from memory.)

For someone who [moved a whole website to
Terraform](/blog/website/03-terraform/) specifically to avoid this feeling, the
irony was getting hard to ignore. I had declarative infrastructure in the cloud
and hand-clicked infrastructure in my own house.

### Ports were a registry in my head

Cockpit took `:9090`, so Prometheus moved to `:9091`. Grafana wanted `:3000`,
so did Homepage, so Grafana became `:3001`. Every one of those decisions was
correct and every one of them existed nowhere except in my head and in the
compose file that happened to encode it.

Add a twelfth service and the first question is "which ports are free?", and
the only way to answer it is to go read every compose file on two machines.

## Why k3s specifically

Kubernetes solves precisely the five things above: it has a scheduler that
knows what each node has, real service discovery by name, health checks that
drive restarts, one declarative source of truth for the whole cluster, and
service ports that are cluster-internal so collisions stop mattering.

The problem is that Kubernetes is also famously enormous, and I have 3.5GB of
RAM across two machines.

[k3s](https://k3s.io/) is Rancher's distribution that strips it down: a single
binary under 100MB, etcd swapped for SQLite by default, and a pile of cloud
provider integrations removed. It's a certified Kubernetes distribution, not a
toy — it's the same API, just packaged for machines like mine.

### Which node is the control plane

Counter-intuitively, the Pi.

|                   | piloma (Pi 5)            | alomalab (laptop) |
| ----------------- | ------------------------ | ----------------- |
| RAM               | 2.0Gi                    | 1.5Gi             |
| Cores             | 4                        | 2                 |
| Network           | Ethernet-capable, stable | WiFi              |
| Uptime discipline | Never touched            | Close the lid     |

The control plane is the component that must never go away — lose it and the
cluster keeps serving traffic but you can't change anything or reschedule
anything. The Pi has more RAM, twice the cores, no lid, and no moving parts.
The laptop is the one with a battery, a WiFi link and a human who occasionally tidies the shelf it lives on.

So: **piloma is the control plane, alomalab is the worker.**

## Local DNS in Pi-hole

Before installing anything, the naming problem needs solving, because "type the
IP address into every config" is what I'm trying to escape.

Using Pi-Hole as a Local DNS Server, I can escape this numbers nightmare.
In **Settings → Local DNS → DNS Records**, map names to node IPs:

```
alomalab.internal    192.168.0.10
piloma.internal      192.168.0.14
```

And in **Local DNS → CNAME Records**, point the per-service names at those:

```
main.alomalab.internal      → alomalab.internal
grafana.alomalab.internal   → alomalab.internal
prom.alomalab.internal      → alomalab.internal
jellyfin.piloma.internal    → piloma.internal
```

A note on why it's shaped this way.

**Use `.internal`, not `.local`.** `.local` is claimed by mDNS/Avahi and you
will get intermittent, maddening resolution failures where it works on one
device and not another. `.internal` was formally reserved for private use, so
nothing on the public internet will ever claim it.

## Installing k3s

On piloma, the control plane:

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --disable local-storage \
  --flannel-backend=host-gw \
  --write-kubeconfig-mode 0644
```

Breaking that down, because every flag here is a real decision:

- **`--disable local-storage`** — k3s ships a local-path provisioner that
  auto-creates PersistentVolumes on the node's disk. I turned it off because my
  storage is one specific 932G drive physically attached to one specific node,
  and I'd rather mount that path explicitly than have a provisioner invent
  volumes on a 29G SD card. The SD card is the thing I least want to write to.
- **`--flannel-backend=host-gw`** — this is the pod network, and it's the flag
  worth understanding.
- **`--write-kubeconfig-mode 0644`** — makes `/etc/rancher/k3s/k3s.yaml`
  readable by my user so `kubectl` works without `sudo`. This is fine for my current setup but it's not a good practice in real worla.

### The host-gw thing

Pods get their own IP addresses on their own network (`10.42.x.x` here), which
must work *across* machines: a pod on alomalab has to reach a pod on piloma.

The default answer, VXLAN, wraps every pod packet inside another UDP packet,
ships it to the other node, and unwraps it. That works over any network
topology, including nodes in different subnets or different data centres, and
it costs you CPU on both ends plus about 50 bytes of overhead per packet.

`host-gw` does the obvious cheaper thing instead: it just adds a route on each
node saying "the `10.42.1.0/24` pod subnet lives at `192.168.0.10`, send it
there". No encapsulation. Packets go out as plain IP.

The catch is that this only works if the nodes are on the same layer-2 network,
because you're relying on them being able to hand each other packets directly.
Both of mine are on the same `192.168.0.0/24` LAN, so that holds. On a Celeron
where CPU is the scarcest thing I own, skipping encapsulation on every single
packet is a real saving.

In short, pod traffic is unencryted locally and using Local Lan setup is fine for this specific case only. Otherwise, you will be exiled.

### Joining the worker

Grab the node token from the control plane:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Then on worker:

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.0.14:6443 \
  K3S_TOKEN=<token> sh -
```

Setting `K3S_URL` is what makes the installer set up an *agent* instead of a
server. Treat that token like a root password for the cluster anyone holding
it can join a node and run workloads.

## It's up

> [!tips]
> Set k as kubectl as kubectl is so *unergonomic* to write
> ```bash
> alias k='kubectl'
> ```

```bash
k get nodes -o wide
```

You should see the *registered nodes* 
```
NAME       STATUS   ROLES           AGE    VERSION        INTERNAL-IP    OS-IMAGE              KERNEL-VERSION                 CONTAINER-RUNTIME
alomalab   Ready    <none>          2d2h   v1.36.3+k3s1   192.168.0.10   Ubuntu 26.04 LTS      7.0.0-29-generic (amd64)       containerd://2.3.2-k3s2
piloma     Ready    control-plane   2d3h   v1.36.3+k3s1   192.168.0.14   Debian GNU/Linux 13   6.18.39+rpt-rpi-2712 (arm64)   containerd://2.3.2-k3s2
```

Two nodes, two architectures, one API.

```bash
kubectl label node alomalab node-role.kubernetes.io/worker=true
```

The cost of the control plane on the Pi:

```
               total        used        free      shared  buff/cache   available
Mem:           2.0Gi       1.3Gi       171Mi       116Mi       646Mi       633Mi
Swap:          2.0Gi       115Mi       1.9Gi
```

That left me with 171MB of memory to be integrated with other services.

Nothing is deployed yet. In the next post I put all the services back, and find
out which of my assumptions about container images survive contact with two CPU architectures.

## Setting Up Kubernetes Dashboard

What's the purpose of a program if there's no dashboard to follow it through.

Before that though, `kubectl get pods` one namespace at a time gets old fast, and I wanted something to glance at from my phone without SSHing into piloma. I followed [this guide](https://medium.com/@howdyservices9/setting-up-kubernetes-dashboard-a-step-by-step-guide-9c479a487001) to get the official Kubernetes Dashboard running.

### 1. Create the yml

The dashboard ships as a single recommended manifest, so there's no need to hand-write anything:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

That creates a `kubernetes-dashboard` namespace and drops in the deployment, service, and RBAC objects it needs. Applying it from piloma means it lands wherever the scheduler decides, not necessarily on piloma itself.

### 2. Export piloma's kubeconfig to the remote client

`kubectl` on piloma works out of the box because k3s writes `/etc/rancher/k3s/k3s.yaml` locally, and I'd already made it world-readable with `--write-kubeconfig-mode 0644` when installing. To drive the dashboard (and the cluster generally) from my actual laptop instead of an SSH session, that file needs to travel:

```bash
scp piloma.internal:/etc/rancher/k3s/k3s.yaml ~/.kube/config
```

The one catch: k3s bakes `server: https://127.0.0.1:6443` into that file, which is correct only on piloma itself. Off the node, that line needs to point at piloma's actual address, so I edited it to:

```yaml
server: https://piloma.internal:6443
```

using the `.internal` name I'd already set up in Pi-hole, rather than hardcoding the IP again.

### 3. `kubectl proxy`

With a working kubeconfig, the dashboard's service is reachable through the API server's built-in proxy. 

```bash
kubectl proxy
```

Then the dashboard is at:

```
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

`kubectl proxy` authenticates using the kubeconfig from step 2, so whatever RBAC permissions that identity has are the permissions the dashboard session gets.

### 4. Create an admin user and grab its token

A `ServiceAccount` with a `ClusterRoleBinding` to `cluster-admin` gets a token with full access to the cluster:

```yaml
# dashboard-admin.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: admin-user
    namespace: kubernetes-dashboard
```

```bash
kubectl apply -f dashboard-admin.yaml
```

Then mint a token for it:

```bash
kubectl -n kubernetes-dashboard create token admin-user
```


Use the output as the Bearer Token for the Dashboard.

Next up, migrating from the Docker Compose to Kubernetes-Based Deployments