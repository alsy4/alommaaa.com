---
title: Putting the Apps Back
date: 2026-08-21
description: Deployments, DaemonSets, and learning what mixed CPU architectures do to your manifests
tags:
  - homelab
  - kubernetes
  - k3s
  - prometheus
  - jellyfin
draft: false
projects:
  - homelab
---

The cluster from [last post](/blog/homelab/02_transitioning_to_kubernetes/) is
empty. Two nodes, an API, and nothing running on it.

Now I have to put back eleven containers that previously lived in compose
files, and the interesting part is that the translation is not one-to-one. Some
things become Deployments, some become DaemonSets, and the choice between them
turns out to be the most useful thing Kubernetes taught me.

Everything goes in one namespace:

```bash
kubectl create namespace homelab
```

A namespace is a naming scope, not a security boundary by default. With one
user and one lab it buys me exactly one thing: `kubectl get all -n homelab`
shows my stuff without k3s's system pods mixed in. That's enough.

# Deployment vs DaemonSet

Before the YAML, the distinction that governs all of it.

A **Deployment** says *"I want N copies of this running somewhere."* You don't
care where. The scheduler picks. If a node dies, the copies come back on
another node. Use it for anything stateless where "which machine" is not part
of the answer: dashboards, web UIs, APIs.

A **DaemonSet** says *"I want exactly one copy on every node."*, the count is however many nodes you have, and it changes automatically
when you add one. Use it for anything whose job is to be *about the node it
runs on*.

Monitoring agents are the textbook case and it's textbook for a good reason.
A metrics exporter that measures the host is meaningless as a Deployment: two
replicas might both land on the same node, and you'd be measuring one machine
twice and the other never.

So:

| Service          | Kind                         | Why                                     |
| ---------------- | ---------------------------- | --------------------------------------- |
| Glance dashboard | Deployment (2 replicas)      | Stateless web UI, don't care where      |
| Grafana          | Deployment                   | Same                                    |
| Prometheus       | Deployment                   | Same, but pinned by its storage         |
| node-exporter    | DaemonSet                    | Measures the node it's on               |
| Glances          | DaemonSet                    | Measures the node it's on               |
| Jellyfin         | Deployment, pinned to piloma | Needs the drive that's physically there |

# Glance: the dashboard

I have known multiple dashboard-ing tools but none compares to my beloved [Glance](https://github.com/glanceapp/glance). 

Two replicas, because it's the page I load from my phone, my laptop and my
desktop, and a rolling update with one replica means a few seconds of nothing.
With two, one stays up while the other restarts. It's a stateless HTTP server
reading a config file; running two costs almost nothing.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: glance
  namespace: homelab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: glance
  template:
    metadata:
      labels:
        app: glance
    spec:
      containers:
        - name: glance
          image: glanceapp/glance:latest
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: config
              mountPath: /app/config
          resources:
            requests:
              memory: "8Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
      volumes:
        - name: config
          configMap:
            name: glance-config
---
apiVersion: v1
kind: Service
metadata:
  name: glance-service
  namespace: homelab
spec:
  selector:
    app: glance
  ports:
    - port: 8080
      targetPort: 8080
```

**The config is a ConfigMap, not a bind mount.** Previously, the 
was mounted from alomalab's disk,
which silently pinned the container to alomalab. A ConfigMap lives in the
cluster's datastore, so both replicas get identical config wherever they land:

```bash
kubectl create configmap glance-config \
  --from-file=glance.yml --from-file=home.yml --from-file=homelab.yml \
  -n homelab
```

The trade-off is that editing config is no longer `vim` over SSH, it's edit
the file, re-apply the ConfigMap, and restart the pods. ConfigMap changes don't
propagate to running pods unless the app watches for them:

```bash
kubectl rollout restart deployment/glance -n homelab
```

**`requests` versus `limits`.** This distinction is the reason I'm here at all,
so it's worth being precise. A **request** is what the scheduler reserves — it
uses the sum of requests on a node to decide whether a new pod fits. A **limit**
is the hard ceiling the kernel enforces. Exceed a memory limit and your
container is killed with `OOMKilled`; exceed a CPU limit and you're throttled,
not killed.

On a 1.5GB node, requests are what stop the scheduler from over-committing the
machine, and limits are what stop one leaky container taking the others down
with it. Both halves are as important as each other.

# node-exporter: the DaemonSet pattern

This is where DaemonSets earn their keep, and where you have to deliberately
break most of the isolation a container normally gives you.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: homelab
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostNetwork: true
      hostPID: true
      containers:
        - name: node-exporter
          image: prom/node-exporter:latest
          args:
            - --path.procfs=/host/proc
            - --path.sysfs=/host/sys
            - --path.rootfs=/host/root
          ports:
            - containerPort: 9100
              hostPort: 9100
          volumeMounts:
            - name: proc
              mountPath: /host/proc
              readOnly: true
            - name: sys
              mountPath: /host/sys
              readOnly: true
            - name: root
              mountPath: /host/root
              readOnly: true
          resources:
            requests:
              memory: "08Mi"
            limits:
              memory: "64Mi"
      volumes:
        - name: proc
          hostPath:
            path: /proc
        - name: sys
          hostPath:
            path: /sys
        - name: root
          hostPath:
            path: /
```

Everything unusual in there exists for the same reason: **a container is
isolated from the host by design, and this container's entire job is to observe
the host.** So you punch holes, deliberately:

- `hostNetwork: true` — use the node's network namespace directly, so the pod
  reports the node's real IP and real interface stats instead of a pod IP.
- `hostPID: true` — see the host's process table, not just its own.
- The three `hostPath` mounts — `/proc` and `/sys` are where the kernel
  publishes everything. Mounted read-only, and under `/host/*` rather than at
  their real paths, so the exporter doesn't confuse them with the container's
  own `/proc`. That's what the `--path.*` args are telling it.

## The headless service

Prometheus needs to scrape both of these. The service for a DaemonSet is a
special case:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: homelab
spec:
  clusterIP: None
  selector:
    app: node-exporter
  ports:
    - port: 9100
```

`clusterIP: None` makes it **headless**. 

A normal service gives you one virtual
IP that load-balances across pods — which is exactly wrong here. Load-balancing
across your metrics exporters means each scrape lands on a random node and your
data is nonsense.

A headless service instead returns *all* the pod IPs from DNS, with no
load-balancing, which is what lets Prometheus discover and scrape each one
individually.

## Prometheus finds them by itself now

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'kubernetes-nodes'
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - source_labels: [__address__]
        regex: '(.*):10250'
        target_label: __address__
        replacement: '${1}:9100'
      - source_labels: [__meta_kubernetes_node_name]
        target_label: instance
```

`kubernetes_sd_configs` means Prometheus asks the Kubernetes API what nodes
exist rather than reading a static list. The relabel rule rewrites the
kubelet's port (`10250`) to the exporter's (`9100`), and copies the node name
into the `instance` label so graphs say `piloma` instead of an IP.

Add a third node and Prometheus scrapes it with no config change. That is the

This needs RBAC, Prometheus is now calling the Kubernetes API, so it needs
permission to list nodes. A ServiceAccount, a ClusterRole with `get`/`list`/
`watch` on `nodes` and `nodes/metrics`, and a ClusterRoleBinding. All of it is
in the repo linked in post 4.

# Glances: same pattern, different reason

Glances is the second DaemonSet, and the manifest is nearly identical:
`hostNetwork: true`, `hostPID: true`, `/proc` and `/sys` mounted read-only,
running in web-server mode on `:61208`.

Same reasoning, different consumer. node-exporter feeds Prometheus for
historical graphs; Glances feeds Glance's dashboard widgets for the live view.
One remembers, one shows now.

# Jellyfin: the pod that can't move

Jellyfin is the exception to everything above. Its library is 257GB of files on
a external hard disk that has been used for external media physically plugged into piloma. No scheduler cleverness relocates
a hard drive.

```yaml
spec:
  nodeSelector:
    kubernetes.io/hostname: piloma
  containers:
    - name: jellyfin
      image: jellyfin/jellyfin:latest
      volumeMounts:
        - name: media
          mountPath: /media
          readOnly: true
  volumes:
    - name: media
      hostPath:
        path: /mnt/media
        type: Directory
```

`nodeSelector` is the blunt instrument: this pod runs on piloma or it doesn't
run. That's correct here — a Jellyfin scheduled onto alomalab would start
happily and serve an empty library, which is worse than not starting.

This is also why I disabled k3s's local-path provisioner in post 2. My storage
isn't a pool to be carved up dynamically; it's one drive in one place.
`hostPath` says exactly that, and the honest cost is that this workload is now
pinned to one machine forever.

**Komga** (comics) and **Syncthing** (file sync) follow the identical pattern —
`nodeSelector` onto piloma, `hostPath` into a subdirectory of `/mnt/media`, a
ClusterIP service, an ingress rule. Once you've written one, you've written all
three, so I won't repeat the YAML.

# The architecture tax nobody warns you about

Two nodes, two CPU architectures: piloma is `arm64`, alomalab is `amd64`.

The scheduler is happy to place a pod on either node. The *image* may not be.
If you deploy something that only publishes `linux/amd64` and it lands on the
Pi, you get:

```
Status: CrashLoopBackOff
exec /entrypoint.sh: exec format error
```

`exec format error` means the kernel was handed a binary compiled for a
different instruction set. It is not a permissions problem, a missing file, or
a bad entrypoint, which is what I spent twenty minutes assuming.

Two ways out. Check first:

```bash
docker manifest inspect <image> | grep architecture
```

Most popular images are multi-arch and this is a non-issue. When one isn't,
pin it explicitly rather than letting the scheduler find out the hard way:

```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: amd64
```

Which reframes something from post 2. I described the mixed architecture as a
curiosity. It's really a *constraint* — one that turns "run this anywhere" into
"run this anywhere it can actually execute", and that's a label you have to
write down yourself.

Right now, we have now way of accessing those services except from using a NodePort. Next post will be about configuring the Local DNS to access those services.