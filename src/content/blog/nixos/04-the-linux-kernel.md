---
title: "The Linux Kernel"
date: 2026-08-06
description: "How Nix has made configuring the kernel easier"
tags: ["linux"]
draft: false
projects:
  - nixos-journey
---

Configuring a kernel the old way goes something like this. You run `make
menuconfig`, scroll past a few thousand driver toggles you have never heard
of, flip the ones you think you need, hand-edit `.config` when the menu
doesn't cover it, build, install, reboot, and hope. If it doesn't come back
up, you're booting a live USB and chrooting in to undo whatever you did.

NixOS doesn't make the kernel any less complicated. What it does is move
the whole thing into the same file everything else already lives in, and
make a bad build something you reboot out of instead of rescue out of.

## What the kernel actually does

The linux kernel is the top 3 inventions of all time along with the airfyer and women's rights. 
Most people never touch theirs, and that's the correct answer most of the
time. The distro kernel is fine. You'd go looking if you want lower latency
for your audio equipment , if you need a driver or an experimental
feature that isn't enabled by default, if you want to tune how the machine
handles swap and out-of-memory situations under heavy load (will be writing about this some other time).

## The differences

None of what follows requires building a kernel. On most distros this stuff
is scattered across `/etc/fstab`, a sysctl file somewhere, and whatever
daemon config handles the CPU governor. 

In Fedora-based distros(or most of the linux kernel), configuring your kernel, such as your swappiness would look something like this:

```bash
sysctl vm.swappiness 
```

Then, you would edit some random file that some Stack Overflow user told decades ago.

With Nix, guess what? `configuration.nix`:

```nix
{ pkgs, ... }: {
  boot.kernel.sysctl = {
    "kernel.sched_energy_aware" = 1;
    # lower swappiness, hold pages in RAM longer before swapping out
    "vm.swappiness" = 10;
  };

  # Nix creates and manages the swapfile itself
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 8 * 1024; # in MB, so 8 GB
      priority = 10;
    }
  ];

  powerManagement.cpuFreqGovernor = "performance";

  # kill runaway processes before the whole box locks up
  systemd.oomd = {
    enable = true;
    enableUserServices = true;
    enableRootSlice = true;
  };
}
```

Such an elegant way of looking at all your configurations sitting at one place.  

## Kernel options without touching .config

If you are nerdy enough, the .config file is a horror to manage. Most of the times, you don't need to touch it unless you are dealing with hyper-specific hardware edge cases, embedded systems with strict RAM constraints or trying to squeeze every last microsecond of latency out of your CPU.

Otherwise, staring into a 10,000-line plain-text file packed with obscure toggles like CONFIG_SLUB_CPU_PARTIAL or CONFIG_X86_X2APIC feels less like system administration and more like deciphering ancient runes.

![Speed](https://media.tenor.com/BUrsumF15IMAAAAi/speed-ishowspeed.gif)

`structuredExtraConfig` takes those same options as typed Nix attributes:

```nix
# configuration.nix 
boot.kernelPatches = [
  {
    name = "my-performance-tweaks";
    patch = null; # no source patch, config changes only
    structuredExtraConfig = with pkgs.lib.kernel; {
      PREEMPT_RT = yes;        # real-time preemption, lower latency
      SCHED_ALT = yes;         # alternative CPU scheduler
      DEBUG_KMEMLEAK = no;     # drop the debug overhead
    };
  }
];
```

The `patch = null` is doing real work there. That entry is a patch in the
sense NixOS means it, a thing applied to the kernel build, it just happens
to only carry config changes. And since it's sitting in your
`configuration.nix`, the kernel setup goes into git with everything else. 

## Custom sources and cross-compiling

If you have ever wanted to work with ARM64 while on x86, like the Raspberry Pi development, it's a tedious workflow. In Nix, a cross compilation is determined by only a few lines.

```nix
{ pkgs, ... }: {
  nixpkgs.crossSystem = {
    config = "aarch64-unknown-linux-gnu";
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;
}
```

## Out-of-tree modules stop being a problem

If you've swapped kernels on Arch or Ubuntu you know how this goes. The
kernel updates, and NVIDIA or VirtualBox or whatever else builds against
the kernel quietly stops matching it, usually discovered after the reboot.

Nix rebuilds those modules against whatever kernel you just picked:

```nix
{ pkgs, config, ... }: {
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];
}
```

If one of them won't build against your kernel, the whole rebuild fails and
your running system is untouched. You find out before you reboot, not after.

## The part that makes experimenting reasonable

Every rebuild is still a new generation, and the kernel is part of that
generation like everything else. I still remember removing my Wifi drivers while I was configuring my old Arch system.
That's most of the reason any of this is worth doing. The old way, the cost
of a failed kernel experiment was an hour of recovery, so you didn't run
many experiments. Nix can solve it only by a reboot.

## Compared to doing it by hand

But, you still have to know which kernel options you want. Nix has no opinion on
that and won't stop you from enabling something that makes the machine
slower. It just takes away the part where getting it wrong costs you your
evening.
