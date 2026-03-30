.PHONY: all
all:
	grep -B99999 'sha256sums=' PKGBUILD | head -n-1 | sponge PKGBUILD
	makepkg --geninteg >> PKGBUILD
	makepkg --verifysource
	makepkg --printsrcinfo > .SRCINFO
