# Installation guide for Ilum

Derived from the archlinux installation guide.

A few sanity checks:
```sh
cat /sys/firmware/efi/fw_platform_size # should be 64
ping ping.archlinux.org # should work
timedatectl # should be correct
```

## Disk partitionning

Recommanded disk layout:
- GPT partition table
- Boot partition:
  - Size: 1G
  - Type: EFI System (`uefi`)
  - Label: `ilum-boot`
- Root partition:
  - Size: rest
  - Type: Linux filesystem (`linux`)
  - Label: `ilum-root`

Use `fdisk` to achive this layout.

## Installation

The package `system-install-scripts` provided a suite of scripts to automate the majority of the installation, in order:
- `system-install prepare` (as root): A one time thing, mainly to generate a custom pacman database for pacstrap later.
- `system-install instal-XXX` (as root): Performs the main installation steps for config `XXX` which may include machine specific steps in between.
- `system-install bundle-user-data` (as root): Creates a (very opiniated) archive of important files belonging to your user and places them in the chroot.
- `system-install finish` (as root): Wraps up the installation by unmounting the install.

As the commands need to be ran as root you need to specify your username to most of them so they can drop down to a working less privileged user.

In action:

```sh
# Generate a pacman database of package necessary packages that aren't in the official repo.
system-install prepare path/to/this/pkgbuilds/repo --build-user $USER

# The actual installation.
system-install install-ilum \
    --bootdev /dev/disk/by-partlabel/ilum-boot \
    --rootdev /dev/disk/by-partlabel/ilum-root \
    --mnt /mnt \
    --create-user $USER \
    --host-user $USER
```

Now that the filesystem is ready, copy over personal data:
- [ ] SSH keys
- [ ] GPG keys
- [ ] Password/Secret files
- [ ] Image folder
- [ ] Commit & push every project
- [ ] Exports settings/data of various apps to import later
    - [ ] PrismLauncher
    - [ ] Firefox
    - [ ] ...

```sh
system-install bundle-user-data --mnt /mnt --host-user $USER --target-user $USER
```

You can now do last seconds stuff with:
```sh
# The -S uses a systemd unit and allows more stuff to be done.
arch-chroot -S /mnt
```

And its done !

```sh
system-install finish --mnt /mnt
reboot
```

## TODO

- [ ] Config for coruscant
- [ ] Config for kuat
- [ ] Setup btrbk hooks
- [x] Script to copy personal data
- [x] Generate `/etc/cmdline.d/root.conf` with the correct partition UUID
