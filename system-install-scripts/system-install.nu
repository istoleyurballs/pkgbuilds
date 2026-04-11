#!/usr/bin/env nu

use std/dirs

def log [message: string] {
  print $"(ansi wb)[(ansi red_bold)ilum-install(ansi wb)](ansi reset) ($message)(ansi reset)"
}

def assert-superuser [] {
  if not (is-admin) {
    log "This commands must be executed as superuser"
    exit 1
  }
}

def assert-mnt-exists [$mnt: path] {
  if not ($mnt | path exists) {
    log $"Mountpoint doesn't exists: (ansi wb)($mnt)(ansi reset)"
    exit 1
  }
}

def mkswappath [mnt: path] {
  $"($mnt)/mnt/rootfs/@swap/swapfile" | path expand
}

# Given a boot and root partition, reformat them with appropriate filesystems and labels.
def "main internal mkfs" [bootdev: path, rootdev: path, mnt: path, user: string, --force] {
  assert-superuser

  log $"Formatting (ansi wb)($bootdev)(ansi reset) as FAT32"
  ^mkfs.vfat -F 32 -n ilum-bootfs $bootdev

  log $"Formatting (ansi wb)($rootdev)(ansi reset) as BTRFS"
  if $force {
    ^mkfs.btrfs --data single --metadata dup --label ilum-rootfs $rootdev --force
  } else {
    ^mkfs.btrfs --data single --metadata dup --label ilum-rootfs $rootdev
  }

  log $"Creating subvolumes on (ansi wb)($rootdev)"
  # Temp mount to create subvolumes
  ^mount --mkdir -t btrfs $rootdev $mnt
  dirs add $mnt

  let user_subvol = $"@home-($user | str kebab-case)"
  ^btrfs subvolume create @ $user_subvol @var-log @var-flatpak @var-docker @swap
  ^btrfs subvolume sync .
  ^btrfs property set @ compression zstd
  ^btrfs property set $user_subvol compression zstd
  dirs drop
  ^umount $mnt
}

# Mount the (assumed) correctly formatted boot and root partitions and mount them to a temporary mountpoint.
def "main internal mount" [bootdev: path, rootdev: path, mnt: path, user: string] {
  assert-superuser

  def mount-rootdev [subvol: string, target: string] {
    let mountpoint = $"($mnt)/($target)" | path expand
    log $"Mounting (ansi wb)($rootdev)[($subvol)](ansi reset) on (ansi wb)($mountpoint)(ansi reset)"
    ^mount --mkdir -t btrfs -o $"subvol=($subvol)" $rootdev $mountpoint
  }

  mount-rootdev @ ''
  mount-rootdev $"@home-($user | str kebab-case)" $"/home/($user)"
  mount-rootdev @var-log /var/log
  mount-rootdev @var-flatpak /var/lib/flatpak
  mount-rootdev @var-docker /var/lib/docker
  mount-rootdev / /mnt/rootfs

  log $"Mounting (ansi wb)($bootdev)(ansi reset) on (ansi wb)($mnt)/boot(ansi reset)"
  ^mount --mkdir -t vfat $bootdev $"($mnt)/boot"
}

# Create a swapfile on an already mounted root partition.
def "main internal mkswap" [mnt: path] {
  assert-superuser

  # Ram size + 1G
  let swapsize = (sys mem | get total | into int) + 1000000000
  let swapfile = mkswappath $mnt

  log $"Creating (ansi wb)($swapsize | into filesize)(ansi reset) of swap at (ansi wb)($swapfile)(ansi reset)"
  ^btrfs filesystem mkswapfile --size $swapsize $swapfile
  ^swapon $swapfile
}

# Create a database file containing all of the packages that aren't in the officials repo.
def "main internal mkpacstrapdb" [build_user: string, pkgbuild_dir: path, db: path] {
  log "Cleaning up database..."
  let db = $db | path expand
  if ($db | path exists) {
    if (glob $"($db)/*" | is-not-empty) {
      rm -rfa ...(glob $"($db)/*")
    }
  } else {
    mkdir $db
  }

  log $"Creating package database for pacstrap at (ansi wb)($db)(ansi reset)"

  def makepkg-aur-append [pkg: string] {
    log $"Building AUR package (ansi wb)($pkg)(ansi reset)"
    
    let dir = mktemp --directory $"system-install-ilum.($pkg).XXXXX"
    dirs add $dir
    ^paru -G $pkg
    ^chmod -R 777 .

    dirs add (glob * | first)
    ^sudo -u $build_user makepkg -c
    mv *.pkg.tar.zst $db

    dirs drop
    dirs drop
    rm -rf $dir
  }
  def makepkg-append [pkg: path] {
    log $"Building local package at (ansi wb)($pkg)(ansi reset)"

    dirs add $pkg
    ^sudo -u $build_user makepkg -c
    mv *.pkg.tar.zst $db
    dirs drop
  }

  makepkg-aur-append paru
  makepkg-append $"($pkgbuild_dir)/archpatch"
  makepkg-append $"($pkgbuild_dir)/system-base"

  log "Creating final database..."

  dirs add $db
  ^repo-add ./custom.db.tar.zst ...(glob *.pkg.tar.zst)
  dirs drop
}

# Execute the pacstrap command with the correct arguments and all.
def "main internal pacstrap" [mnt: path, package: string] {
  assert-superuser

  log $"Creating file structure with (ansi wb)pacstrap(ansi reset)"
  ^pacstrap -C /usr/share/system-install-scripts/pacstrap.conf -K -i $mnt $package
}

def "main internal mkuser" [mnt: path, user: string, host_user: string] {
  assert-superuser

  log $"Creating user (ansi wb)($user)(ansi reset)"
  ^arch-chroot $mnt useradd --user-group --home-dir /home/($user) ($user)
  log $"Setting password for user (ansi wb)($user)(ansi reset)"
  ^arch-chroot $mnt passwd $user

  log $"Adding to (ansi wb)sudo(ansi reset) group"
  ^arch-chroot $mnt groupadd -f sudo
  ^arch-chroot $mnt usermod -aG sudo $user
  ^arch-chroot $mnt chown -R $"($user):($user)" $"/home/($user)"

  log "Setting shell"
  ^arch-chroot $mnt chsh -s /usr/bin/fish $user

  log "Setting up dotfiles"
  sudo -u $host_user git clone --recursive git@github.com:istoleyurballs/dotfiles.git $"($mnt)/home/($user)/dotfiles"
  ^arch-chroot $mnt chown -R $"($user):($user)" $"/home/($user)/dotfiles"
  ^arch-chroot -S -u $user $mnt bash -c $"cd /home/($user)/dotfiles && make paru"
}

def "main internal finalize-ilum" [mnt: path, user: string] {
  log $"Installing the rest of the packages for (ansi wb)system-ilum(ansi reset)"
  ^arch-chroot -S -u $user $mnt paru -Syu system-ilum

  log "Installing flatpak packages"
  ^arch-chroot -S $mnt ilum-flatpak install

  log $"Installing the rest of dotfiles"
  ^arch-chroot -S -u $user $mnt bash -c $"cd /home/($user)/dotfiles && make"

  log "Setting up bootloader"
  ^arch-chroot $mnt ilum-boot install
}

def "main internal finalize" [mnt: path] {
  assert-superuser

  log "Generating fstab"
  ^genfstab -L $mnt o> $"($mnt)/etc/fstab"
  log "Generating locales"
  ^arch-chroot $mnt locale-gen
  log "Changing root password"
  ^arch-chroot $mnt passwd
}

# === Main commands

def "main prepare" [pkgbuild_dir: path, db: path = "/var/cache/system-install-scripts/db", --build-user: string = "nobody"] {
  main internal mkpacstrapdb $build_user $pkgbuild_dir $db
}

def "main install-ilum" [--bootdev: path, --rootdev: path, --mnt: path = "/mnt", --create-user: string, --host-user: string --force] {
  if not ($bootdev | path exists) {
    log $"Boot device doesn't exists: (ansi wb)($bootdev)(ansi reset)"
    exit 1
  }
  if not ($rootdev | path exists) {
    log $"Root device doesn't exists: (ansi wb)($rootdev)(ansi reset)"
    exit 1
  }
  assert-mnt-exists $mnt
  if ($create_user | is-empty) {
    log $"Please specify a username with `--create-user`"
    exit 1
  }
  if ($host_user | is-empty) {
    log $"Please specify a host user with `--create-user`"
    exit 1
  }

  main internal mkfs $bootdev $rootdev $mnt $create_user --force=$force
  main internal mount $bootdev $rootdev $mnt $create_user
  main internal mkswap $mnt
  main internal pacstrap $mnt system-base
  main internal mkuser $mnt $create_user $host_user
  main internal finalize-ilum $mnt $create_user
  main internal finalize $mnt
}

# A very opiniated way to build an archive of important files to keep and transfer to the new system.
def "main bundle-user-data" [...additional_paths: string, --mnt: path = "/mnt" --host-user: string, --target-user: string] {
  assert-mnt-exists $mnt
  if ($host_user | is-empty) {
    log $"Host user is empty"
    exit 1
  }
  if ($target_user | is-empty) {
    log $"Target user is empty"
    exit 1
  }

  let host_home = $"/home/($host_user)"
  let target_home = $"($mnt)/home/($target_user)"

  if not ($host_home | path exists) {
    log $"Host user doesn't have a home ?"
    exit 1
  }
  if not ($target_home | path exists) {
    log $"Target user doesn't have a home at mountpoint"
    exit 1
  }

  let tmp = mktemp --directory "system-install.export.XXXX"
  let export = mktemp "system-install.export.XXXX.tar"

  dirs add $host_home

  let ssh_keys = glob $"./.ssh/*.{key,key.pub}"
  if ($ssh_keys | is-not-empty) {
    log "Copying SSH keys"
    ^tar --append -f $export ...($ssh_keys | path relative-to ("." | path expand))
  }

  dirs add $tmp
  ^sudo -u $host_user gpg --armor --export o> pub.gpg.asc
  if (du pub.gpg.asc | get 0.apparent | into int) > 0 {
    log "Exporting GPG public keys"
    ^tar --append -f $export pub.gpg.asc
  }
  ^sudo -u $host_user gpg --armor --export-secret-keys o> sec.gpg.asc
  if (du pub.gpg.asc | get 0.apparent | into int) > 0 {
    log "Exporting GPG secret keys"
    ^tar --append -f $export sec.gpg.asc
  }
  dirs drop

  log "Copying pictures folder"
  ^tar --append -f $export Pictures

  log "Copying document folder"
  ^tar --append -f $export Documents

  log "Copying secrets folder"
  ^tar --append -f $export Secrets

  if ($additional_paths | is-not-empty) {
    log "Copying additional files"
    ^tar --append -f $export ...($additional_paths | path relative-to ("." | path expand))
  }

  log $"Moving to (ansi wb)($target_home)(ansi reset)"
  mv -p $export $"($target_home)/export.tar"
  ^arch-chroot -S $mnt chown $"($target_user):($target_user)" $"/home/($target_user)/export.tar"

  dirs drop

  rm -r $tmp

  log $"Checking for uncommited/pushed changes in (ansi wb)~/Dev(ansi reset)"
  ls $"($host_home)/Dev"
    | insert git_committed {|d| dirs add $d.name; (^git diff-index --quiet origin/HEAD | complete | get exit_code) == 0}
    | insert git_pushed {|d| dirs add $d.name; (^git remote get-url origin | complete | get exit_code) == 0}
    | where not $it.git_committed or not $it.git_pushed
    | each {|d| log $" - Project (ansi wb)($d.name | path relative-to $host_home)(ansi reset) has local only changes !" }

  null
}

def "main finish" [--mnt = "/mnt"] {
  assert-superuser
  assert-mnt-exists $mnt

  log "Disabling swap"
  ^swapoff (mkswappath $mnt)

  log "Unounting everything"
  ^umount -R -v $mnt
}

def main [] {
  help main
}

# vim: set tabstop=2 shiftwidth=2 expandtab :
