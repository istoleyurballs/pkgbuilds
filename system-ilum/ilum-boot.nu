#!/usr/bin/env nu

def log [message: string] {
  print $"(ansi wb)[(ansi red_bold)ilum-boot(ansi wb)](ansi reset) ($message)(ansi reset)"
}

def "main install" [
  --esp: path = "/boot",
  --disk: path = "/dev/disk/by-partlabel/ilum-boot",
  --partition: int = 1,
  --root: path = "/"
] {
  if not (is-admin) {
    print "ERROR: This commands needs superuser privileges"
    exit 1
  }

  log $"Generating (ansi wb)/etc/cmdline.d/root.conf(ansi reset)"
  let root_uuid = ^findmnt -J --output=uuid $root | from json | get filesystems.0.uuid
  $"root=UUID=($root_uuid)" > /etc/cmdline.d/root.conf

  log "Building the EFI executable"
  mkdir $"($esp)/EFI/Linux"
  ^mkinitcpio -p linux
  
  log $"Adding a boot entry for (ansi wb)arch-linux-fallback.efi(ansi reset)"
  (^efibootmgr --create
    --disk $disk --part $partition
    --label 'Arch Linux (fallback)' --loader '\EFI\Linux\arch-linux-fallback.efi' --unicode)

  log $"Adding a boot entry for (ansi wb)arch-linux.efi(ansi reset)"
  (^efibootmgr --create
    --disk $disk --part $partition
    --label 'Arch Linux' --loader '\EFI\Linux\arch-linux.efi' --unicode)

  log "Cleaning duplicated boot entries"
  ^efibootmgr --remove-dups
}

def main [] {
  help main
}

# vim: set tabstop=2 shiftwidth=2 expandtab :
