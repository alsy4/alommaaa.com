---
title: "Homelab"
description: "Two second-hand machines, a Raspberry Pi and a dying laptop, turned into a k3s cluster"
date: 2026-08-13
status: "active"
draft: false
---

# Intro

In addition to my current homelab setup, I am *refurbishing* my very-old, unused laptop from my mom and a Raspberry Pi into a k3s setup. 


- **piloma** — Raspberry Pi 5 (4C Cortex-A76, 2GB RAM, Debian 13 trixie, arm64),
  with a 932G external drive hanging off USB at `/mnt/media`.
- **alomalab** — Acer Aspire ES1-131 laptop (Intel Celeron N3050, 2C/2T, 1.5GB
  RAM, Ubuntu 26.04) looking at the spec of this laptop, it's better of being an e-waste.

It started as two independent Docker hosts glued together with Portainer agents
and hardcoded IPs. It is now a two-node k3s cluster with piloma as the control
plane and alomalab as the worker.

Both of this cluster has a sum of 4GB RAM which is less than a single tab of a chromium-based browser and it still can serve up to 2k of media to the whole house.