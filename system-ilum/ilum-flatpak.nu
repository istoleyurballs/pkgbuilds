#!/usr/bin/env nu

def "main install" [] {
  (^flatpak install flathub
        com.github.tchx84.Flatseal
        com.google.Chrome
        com.discordapp.Discord
        com.spotify.Client
        org.jellyfin.JellyfinDesktop
        org.kde.filelight
        org.prismlauncher.PrismLauncher
        org.gimp.GIMP
        org.blender.Blender
        edu.berkeley.BOINC
        com.prusa3d.PrusaSlicer)
}

def main [] {
  print "Usage: install"
  exit 1
}

# vim: set tabstop=2 shiftwidth=2 expandtab :
