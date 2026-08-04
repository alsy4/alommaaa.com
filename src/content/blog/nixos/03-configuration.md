---
title: "Understanding configuration.nix"
date: 2026-08-04
description: "What's actually going on inside configuration.nix, and why it beats hand-tuning a normal Linux box"
tags: ["linux"]
draft: false
projects:
  - nixos-journey
---

Last post I dumped a working `configuration.nix` on you and moved on. This time, we are about to deep dive into the main component of Nix, `configuration.nix`.

## How it works

`configuration.nix` is a Nix expression, a function that takes `pkgs`,
`lib`, `config`, and friends, and returns an attribute set describing what
the whole system should look like. Not what you ran, not what you happened
to install last Tuesday, what it should look like, full stop.

```nix
{ config, pkgs, ... }:

{
  services.openssh.enable = true;
}
```


That's a module. NixOS ships with hundreds of these built in, one for
`openssh`, one for `nginx`, one for `postgresql`, each defining a set of
typed options with sane defaults. Setting `services.openssh.enable = true`
doesn't run a script, it flips a switch in that module's option tree.
When you run `sudo nixos-rebuild switch`, Nix evaluates your whole config,
merges every module's options together, builds the resulting system as one
big derivation, and symlinks it into `/run/current-system`. Then it adds a
new entry to the bootloader for that build. Nothing is mutated in place.

This is also why `hardware-configuration.nix` from the last post stays
separate. It's the machine-specific stuff, disk UUIDs, kernel modules,
things `nixos-generate-config` figured out by looking at your actual
hardware. Your `configuration.nix` imports it and builds on top, so the
file you actually edit stays hardware-agnostic.

## Basic setup

Strip the GNOME example from last post down to the bare minimum and this
is what's left:

```nix
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos";

  users.users.yourname = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  system.stateVersion = "25.05";
}
```

No desktop, no extra packages, just enough to boot into a TTY and log in.
`system.stateVersion` deserves a callout since it trips people up. It's not
a "current NixOS version" field, it's pinned to whatever version you
installed with, and it locks the default behavior of certain services so a
future NixOS upgrade doesn't silently change how your system already
behaves. Don't bump it just because a newer release exists. Leave it alone
unless you've actually read what changed.

Once you've edited the file, `sudo nixos-rebuild switch` applies it and
adds a boot entry immediately. `nixos-rebuild test` applies it without
adding that entry, good for trying something risky. `nixos-rebuild boot`
builds it but only switches on the next reboot. And since every switch is a
new generation, breaking something is never fatal, just reboot and pick the
older entry from the bootloader menu.

## Most common settings for user

The options you'll actually touch, roughly in the order you'll want them:

- `networking.networkmanager.enable`: turns on NetworkManager for wifi.
  Without it you're stuck configuring interfaces by hand.
- `time.timeZone`: something like `"Asia/Kuala_Lumpur"`. Gets this wrong
  once and every log timestamp is a headache.
- `i18n.defaultLocale`: usually `"en_US.UTF-8"` unless you want a different
  system language.
- `users.users.<name>.extraGroups`: `"wheel"` gets you sudo, `"video"` and
  `"audio"` matter for some hardware setups, `"docker"` if you're running
  containers without sudo every time.
- `services.openssh.enable`: if this box needs to be reachable over SSH.
- `zramSwap.enable`: compressed RAM-backed swap, no separate swap
  partition needed, and it's basically free on modern hardware.
- `hardware.bluetooth.enable` and `services.pipewire`: bluetooth and audio,
  both off by default on a minimal install.

Two of those, `networking.networkmanager` and `services.pipewire`, are
actually short for a handful of related sub-options with their own
defaults, so it's worth reading through what each one turns on rather than
copying blindly.

## How to install new programs

There are three ways to get a program onto a NixOS box, and which one you
want depends on how permanent you want it to be.

The first is `environment.systemPackages`, the one from last post's
example:

```nix
environment.systemPackages = with pkgs; [
  discord
  git
  neovim
];
```

Add the name, rebuild, it's there for every user on the system. This is
the default answer for most things.

The second is a `programs.<name>` module, when one exists. Not every
package has one, but some do, and they're worth using when available
because they set up more than just the binary. `programs.git.enable = true`
for example also lets you configure git settings declaratively.
`programs.steam.enable = true` handles the extra sandboxing and 32-bit
libraries Steam needs, something plain `systemPackages` would leave you to
figure out by hand.

The third is `nix-shell -p <package>`, or its newer form `nix shell
nixpkgs#<package>`. This drops you into a shell with that package
available and nothing else changes, no edit to `configuration.nix`, no
rebuild. The second you exit the shell, it's like it was never installed.
Good for "let me just try this tool once" without committing to it.

For finding package names, `search.nixos.org` is the easiest, or run `nix
search nixpkgs <name>` from the terminal. Once you know the name, add it to
`systemPackages` and run `sudo nixos-rebuild switch`.

One thing I'm deliberately not covering here: per-user package management
with home-manager, which is a different, more granular way to handle
dotfiles and personal tools without touching the system-wide config at
all. That's a big enough topic to get its own post.

## Why it's better than usual Linux setup

On Arch, my old setup, installing something meant `pacman -S <package>`,
maybe editing a config file by hand afterward, maybe enabling a systemd
service, and six months later having no memory of why half of it was
there. Uninstalling never fully cleaned up either, leftover config files
in `/etc`, services still enabled, cruft nobody remembers adding.

None of that happens here. Every package, every service, every user
account traces back to one file. Delete a line from `systemPackages` and
rebuild, and that package is gone, actually gone, not just unlinked from
PATH with its config still sitting around. `git diff` on `configuration.nix`
shows you exactly what changed on the machine between two points in time,
which is not something `pacman -Qe` or a `dnf history` log gives you with
anywhere near the same clarity.

Rebuilds are also atomic in a way manual changes never are. If a rebuild
fails partway through, the running system doesn't change, you're still on
the last working generation. Compare that to a `dnf update` that dies
halfway and leaves half your packages on old versions and half on new
ones.

And because the whole system state lives in that one file, moving to a
new machine is copy `configuration.nix`, swap in a fresh
`hardware-configuration.nix` for the new hardware, rebuild. Same system,
different box.

Next post is probably home-manager, since `systemPackages` covers the
system but says nothing about dotfiles or per-user tooling, and that gap
is the next thing worth solving.
