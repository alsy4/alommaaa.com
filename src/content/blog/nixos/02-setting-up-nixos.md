---
title: "Setting Up NixOS"
date: 2026-08-04
description: "Spinning up nixos using existing Linux-partition(ext4)"
tags: ["linux"]
draft: false
projects:
  - nixos-journey
---

There are mainly 2 ways to spin up a new Operating System(OS) in your device.
## Using a USB Drive
This step is quite simple and if you have experiences "burning" your unused USB flash drives, it will be quite straightforward.
1. Download the official ISO from [NixOS Official Download](https://nixos.org/download/)
2. Burn the ISO File into your Installation Media (I personally like Ventoy, there are other tools such as BalenaEtcher, Rufus or even Raspberry Pi Imager)
3. Boot into the Media [Guide](https://www.google.com/search?q=how+to+boot+into+installation+media&ie=UTF-8)
4. Follow the GUI Steps
## Using an existing Linux Installation
This will be the main focus of this post since I am currently dual-booting Fedora and Arch(btw) and I am uninstalling Arch to replace it with Nix. So let's learn about Linux while we install NixOS
### 1. Partition
If you have 512GB of SSD in your laptop, you can split it to have 256GB of Windows and 256GB of Linux. That's what I did when I first started going down this rabbit hole. This is called **Dual Booting**
Check the partitions with:
```bash
lsblk -f
```
For me it returns:
```
NAME        FSTYPE FSVER LABEL  UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
zram0       swap   1     zram0  5657b3f9-49f1-4f35-adf6-8eb02cb913df                [SWAP]
nvme0n1
├─nvme0n1p1 vfat   FAT32        6DF4-C663                             939.4M    12% /boot/efi
├─nvme0n1p2 ext4   1.0   arch   a1bd3e58-f504-442e-8bd0-c7adbedcc5f9
├─nvme0n1p3 ext4   1.0          2da83770-faac-41ea-b2bc-de373a91fe95  999.2M    43% /boot
└─nvme0n1p4 btrfs        fedora b82681b6-0951-4272-abdd-6e53fbec6737  165.3G    23% /home
```
This might look overwhelming but Linux is really simple once you get the hang of it.

Let's read this table like a filing cabinet, one drawer at a time:

- **`zram0`**: ignore this one, it's just compressed RAM pretending to be swap space. Not a real disk partition.
- **`nvme0n1`**: this is the physical drive itself. Everything indented under it is a slice *of* that one drive.
- **`nvme0n1p1`**: tiny partition, `vfat` filesystem, mounted at `/boot/efi`. This is the **EFI System Partition**, or **ESP** for short. Every OS on your machine that boots via UEFI (which is basically every modern install) needs its boot files to live somewhere your motherboard's firmware can find and read *before* Linux itself has even started. That "somewhere" is this partition. Notice it has no label saying "fedora" or "arch", which is your first clue it's **shared**. Both of my distros keep their boot files in here, in their own subfolders. This is the one partition on the whole disk I am not allowed to touch.
- **`nvme0n1p2`**: labelled `arch`, `ext4`, and (important detail) **no mountpoint**. That blank space under `MOUNTPOINTS` tells you it's not currently in use. Which makes sense: I took this screenshot while sitting inside Fedora, not Arch. Arch is just sitting there on disk, unused, waiting to be evicted.
- **`nvme0n1p3`**: Fedora's own `/boot`. This is different from the ESP! The ESP holds the tiny bootloader stub; this partition holds the actual Linux kernel and initial ramdisk Fedora boots into.
- **`nvme0n1p4`**: Fedora's root filesystem (`btrfs`), mounted at `/home` (and, off-screen, also `/`; btrfs lets one partition serve both).

So translating all that jargon into one sentence: **I'm currently running Fedora, Arch is the unused partition `p2`, and there's one shared boot partition `p1` that I must never format.**

That last part is the one rule that matters most here. If you format the wrong partition, you don't just lose Arch, you lose Fedora's ability to boot too, since its boot files live in that same shared spot. So before running any format command, always re-run `lsblk -f` and just double, triple check the label and UUID match what you expect. There's no undo button on this one.

With that confirmed, wiping Arch is one command:

```bash
sudo mkfs.ext4 -L nixos -F /dev/nvme0n1p2
```

Breaking down what each piece does, since none of this is obvious if you haven't seen it before:
- `mkfs.ext4`: "make filesystem, ext4 flavor." This is what actually erases what's there and lays down a fresh, empty filesystem.
- `-L nixos`: gives the new partition a human-readable label, so later commands can refer to it as `nixos` instead of memorizing a UUID.
- `-F`: force, skip the confirmation prompt. Handy once you're sure, dangerous if you're not, and the part to slow down on.

Run it, and Arch (btw) is gone. Onto turning this empty partition into something bootable.

### 2. Mount

"Mounting" trips a lot of beginners up because it sounds abstract, but the idea is simple: a partition on its own is just raw storage, invisible to your file browser or terminal until you tell Linux *where in the folder structure* it should appear. Mounting is that act of plugging it in.

We're about to build a new operating system, so we need a workbench to build it on: a temporary folder where our new NixOS install lives while we're setting it up, before it's ever bootable on its own. The convention is `/mnt`:

```bash
sudo mount /dev/disk/by-label/nixos /mnt
```

That `by-label/nixos` is just referencing the label we set two steps ago instead of typing out `/dev/nvme0n1p2` again: same partition, friendlier name.

Now we need somewhere for boot files to live *inside* that workbench, mirroring how it'll actually look once installed:

```bash
sudo mkdir -p /mnt/boot
```

And here's the part specific to a shared-ESP setup like mine. The ESP (`p1`) is *currently* mounted at `/boot/efi` for Fedora's benefit. We need to temporarily borrow it and mount it at `/mnt/boot` instead, so our new NixOS files land in the right shared spot:

```bash
sudo umount /boot/efi
sudo mount /dev/nvme0n1p1 /mnt/boot
```

Why unmount it first instead of just mounting it a second time at the new path? Because a single partition mounted in two places at once is like trying to be in two rooms simultaneously, technically possible, but the next tool we run gets confused about which one is "real" and writes broken configuration because of it. One mount, one path, no exceptions.

### 3. Install Nix

Quick but important distinction before we go further: **Nix** and **NixOS** are not the same thing. NixOS is the full operating system. Nix is the package manager underneath it, and Nix also happens to run perfectly fine as a guest on totally unrelated distros, Fedora included. That's the trick we're using here: rather than booting a NixOS installation USB, we're installing Nix *inside* our currently-running Fedora, and using it as a tool to build NixOS onto that empty partition next door.

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Once that finishes, grab the extra tools that aren't included by default:

```bash
nix-env -iA nixpkgs.nixos-install-tools
```

This gives you two new commands, `nixos-generate-config` and `nixos-install`, which is everything we need from here on.

One small annoyance worth flagging early: running these with `sudo` sometimes fails with "command not found," even though they clearly just installed. That's because `sudo` runs with a stripped-down environment that doesn't know about your personal Nix install. The fix is to resolve the full path yourself before handing it to `sudo`:

```bash
sudo $(which nixos-install) --root /mnt
```

You'll see this pattern repeated for every Nix command from here on.

### 4. Generate a Config

```bash
sudo $(which nixos-generate-config) --root /mnt
```

This command looks at everything currently mounted under `/mnt` and writes two files describing it, into `/mnt/etc/nixos/`:

- **`hardware-configuration.nix`**: the boring, auto-generated part. Disk UUIDs, detected kernel modules, CPU details. You'll basically never hand-edit this.
- **`configuration.nix`**: the fun part, and the one you actually write yourself. This is where you say what you *want* your system to be: hostname, desktop environment, which programs are installed, user accounts, everything.

This split is very much a "NixOS thing," and it's worth pausing on because it's genuinely different from most distros. On Fedora or Arch, your system's state is whatever accumulated from years of `pacman -S` and `dnf install` commands, config file edits, and half-remembered troubleshooting. On NixOS, `configuration.nix` *is* the system, in full, in one file (or a few). Wipe it and rebuild from the same file, and you get the exact same machine back. That's most of the appeal.

Before moving on, peek inside the generated hardware file:

```bash
cat /mnt/etc/nixos/hardware-configuration.nix
```

Look for a section starting with `fileSystems."/boot"`. You should see exactly **one** of these blocks, with `fsType = "vfat"`. If step 2 got mounted correctly, that's all you'll see. (If you ever see this block appear twice, it means the ESP got mounted in two places at once somewhere along the way: delete the extra, bogus-looking one by hand.)

### 5. Write configuration.nix

```bash
sudoedit /mnt/etc/nixos/configuration.nix
```

Here's a beginner-friendly starting point, with GNOME as the desktop:

```nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 5;

  # Since the ESP is shared with Fedora, its boot files are already
  # sitting right there — we just need to tell our new bootloader
  # about them so Fedora still shows up as an option.
  boot.loader.systemd-boot.extraEntries = {
    "fedora.conf" = ''
      title Fedora
      efi /EFI/fedora/shimx64.efi
    '';
  };

  # Basic system info
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Kuala_Lumpur";
  i18n.defaultLocale = "en_US.UTF-8";

  zramSwap.enable = true;

  # Desktop environment
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb.layout = "us";

  # Your user account — replace with your own username
  users.users.yourname = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ]; # "wheel" = allowed to sudo
  };

  environment.systemPackages = with pkgs; [
    firefox
    git
    wget
  ];

  system.stateVersion = "25.05";
}
```

A couple of things worth explaining line-by-line for anyone new to this:
- `boot.loader.systemd-boot.enable`: this is your bootloader, the thing that shows a menu at startup and actually launches your OS. NixOS defaults to `systemd-boot`, which is simpler than GRUB if you don't need anything fancy.
- `extraEntries`: this is the chainloading trick. It doesn't reinstall or duplicate Fedora, it just adds a menu entry that says "go run *this* file over here," pointing straight at Fedora's own boot file. Before trusting this, confirm the file actually exists:
  ```bash
  ls /mnt/boot/EFI/fedora/
  ```
  If you see `shimx64.efi`, great, the config above is correct. If instead you only see `grubx64.efi`, swap the path in `extraEntries` to point at that one.
- `users.users.yourname`: swap `yourname` for whatever you want your actual username to be. This also determines your home folder path (`/home/yourname`).

### 6. Install

```bash
sudo $(which nixos-install) --root /mnt
```

This is the big one: it downloads and builds your entire system according to what you wrote in `configuration.nix`, then installs the bootloader. With a full desktop environment like GNOME, this can take a while, so don't panic if it sits there for a few minutes. Near the end, it'll prompt you to set a **root password**, so go ahead and set one, don't skip past it.

Before you do anything else (don't even think about rebooting yet), confirm the install genuinely finished:

```bash
ls -la /mnt/nix/var/nix/profiles/system
```

You're looking for a symlink, something like `system -> system-1-link`. If that's there, congratulations, you have a real, working NixOS system sitting on disk. If it's missing, scroll back up through the install output: something failed partway through, and no amount of fiddling with later steps will fix a system that never finished building.

### 7. Set a Password

Root has a password now, but your actual user account (`yourname`) doesn't yet, and you'll want to log in as that, not root, once you're inside GNOME.

The tool for this is `nixos-enter`, which temporarily "steps into" your new, not-yet-booted system so you can run commands as if you were already running it:

```bash
sudo $(which nixos-enter) --root /mnt -c 'passwd yourname'
```

If your host system is Fedora specifically, you might hit this:

```
unshare: mount /proc failed: Operation not permitted
```

This is Fedora's SELinux security system being extra cautious about the sandboxing `nixos-enter` needs. A quick, temporary workaround:

```bash
sudo setenforce 0
sudo $(which nixos-enter) --root /mnt -c 'passwd yourname'
sudo setenforce 1
```

(`setenforce 0` briefly relaxes SELinux, `setenforce 1` turns it right back on once you're done. Don't leave it off longer than necessary.)

If instead you get `passwd: command not found` even though `nixos-enter` ran, that's a separate quirk: the environment inside the chroot didn't pick up the right PATH. The most reliable fallback is to skip `nixos-enter` and do the chroot by hand, calling `passwd` by its exact location:

```bash
sudo mount --bind /dev  /mnt/dev
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys  /mnt/sys

sudo chroot /mnt /nix/var/nix/profiles/system/sw/bin/passwd yourname

sync
sudo umount /mnt/dev /mnt/proc /mnt/sys
```

A chroot, if you haven't met the term before, briefly fools a program into thinking a folder (`/mnt` here) is the real root of the filesystem (`/`), even though you're still technically running the old system. It's how you can run commands "as" your new install without rebooting into it first.

### 8. Reboot and Clean Up

Unmount everything cleanly, and give Fedora its ESP mount back the way it was before we started:

```bash
sync
sudo umount /mnt/boot
sudo umount /mnt
sudo mount /dev/nvme0n1p1 /boot/efi
sudo reboot
```

When your laptop restarts, you should see a boot menu with two options: **NixOS** and **Fedora**. That menu is our `systemd-boot` config talking directly to your motherboard's firmware. Remember from step 1, the firmware doesn't care which OS is "installed," it just runs whatever bootloader file it's pointed at. Pick NixOS, and if you set up GNOME like the example above, you'll land on a login screen. Log in with `yourname` and the password from step 7.

Once you've confirmed everything boots and logs in correctly, the very last bit of housekeeping is clearing out what's left of Arch:

```bash
sudo rm -rf /boot/efi/EFI/arch
sudo efibootmgr -v
```

The `efibootmgr -v` command lists every OS your motherboard's firmware currently knows about by name. Find the line for "arch" and note its entry number, then:

```bash
sudo efibootmgr -b XXXX -B
```

(swap `XXXX` for that number), and Arch is fully gone, both from disk and from your firmware's memory. Fedora's own files, on the other hand, were never touched through any of this. That's the entire point of being careful about which partition we formatted back in step 1.

Welcome to NixOS. If any of `configuration.nix` still feels unfamiliar, don't worry, that's genuinely a whole topic on its own, and one I'll get into in a future post.

References:
[NixOS Manual](https://nixos.org/manual/nixos/stable/#sec-installation) \
[Official Installation Guide](https://nixos.wiki/wiki/NixOS_Installation_Guide)
