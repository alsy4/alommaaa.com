---
title: "What is NixOS"
date: 2026-08-03
description: "What NixOS actually is, and why I switched to it"
tags: ["linux"]
draft: false
projects:
  - nixos-journey
---

Before I get into actually setting the thing up, probably worth explaining
what NixOS even is. 

NixOS is a Linux distro built on top of the Nix package manager. The whole
system, packages, services, users, kernel modules, dotfiles, all of it, gets
described in one configuration file (or a handful of them if you're using
flakes). Rebuild from that file and you get the same machine every time.
That's the pitch. 

## Most distros work backwards from this

You apt install a thing, systemctl enable another thing, edit a config file
by hand, and six months later have no idea how the machine got the way it
is. I've done this to myself more times than I'd like to admit.

NixOS does not work like that. `/etc/nixos/configuration.nix` is the source
of truth. Run `nixos-rebuild switch` and it rebuilds the whole system to
match that file exactly. Nothing gets installed on the side.

```nix
environment.systemPackages = with pkgs; [
  git
  neovim
  ripgrep
];

services.openssh.enable = true;
```

That's the whole config for "these packages exist and ssh is on." No
digging through shell history trying to remember why `ripgrep` is on this
box and not the other one.

## Why I actually care about this

A few things sold me on it.

Same config, same result, every machine, every time. "Works on my machine"
stops being an excuse and starts being something you can just git clone
and check.

You can say these kind of technologies such as Docker, Kubernetes and Terraform impresses me everytime. It's ability to simplify things.

Every rebuild is a new generation in the bootloader. Break something with
an upgrade? Reboot, pick the old generation, done. No half-upgraded system
to untangle.

Packages live in `/nix/store`, in paths keyed off a hash of everything that
went into building them. Two versions of the same library can sit right
next to each other without stepping on each other, because they're never
actually in the same spot.

And `nix-shell -p <package>` drops you into a shell with that package
available, then it's gone the second you leave. Nothing sticks around on
the base system.

## It's not free though

The Nix language takes a while to click, and the error messages are not
exactly friendly when something goes wrong. Most software assumes the
normal filesystem layout, `/usr/bin`, `/lib`, that kind of thing, so
anything that doesn't get along with `/nix/store` needs a wrapper or
`nix-ld` to work at all.

Still. Once the config's actually written, you end up with a system that's
version controlled, portable, and boring in the best way. After years of
distro hopping that's exactly what I was after.

[Next post](/blog/nixos/02-setting-up-nixos): actually installing this thing.