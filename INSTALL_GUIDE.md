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

Install the `system-install-scripts` package manually and just run it:

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
- [ ] Exports of various apps to import later
    - [ ] PrismLauncher

You can now do last seconds stuff like generating SSH key and whatnot with:
```sh
arch-chroot /mnt
```

And its done !

```sh
umount -Rl /mnt
reboot
```

## TODO

- Config for coruscant
- Config for kuat
- Setup btrbk hooks
- Script to copy personal data
