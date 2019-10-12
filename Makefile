# GNU make is required to run this file. To install on *BSD, run:
#   gmake PREFIX=/usr/local install

PREFIX ?= /usr
IGNORE ?=
THEMES ?= $(patsubst %/index.theme,%,$(wildcard ./*/index.theme))
IS_UBUNTU ?= $(shell [ "$$(lsb_release -si 2> /dev/null)" = Ubuntu ] && echo true)
PKGNAME = flat-remix-gnome
MAINTAINER = Daniel Ruiz de Alegría <daniel@drasite.com>


# excludes IGNORE from THEMES list
THEMES := $(filter-out $(IGNORE), $(THEMES))

all:
	# skip background-sync when packaging
	$(if $(DEB_BUILD_OPTIONS),, cd src && HOME=$$(eval echo ~$$SUDO_USER) ./build.sh --login-background $$(gsettings get org.gnome.desktop.background picture-uri | cut -c 9-| rev | cut -c 2- | rev))

build:
	cd src && ./build.sh -r

install:
	mkdir -p $(DESTDIR)$(PREFIX)/share/themes
	cp -a $(THEMES) $(DESTDIR)$(PREFIX)/share/themes/
	mkdir -p $(DESTDIR)$(PREFIX)/share/gnome-shell/theme
	$(foreach theme, $(THEMES), ln -sf $(PREFIX)/share/themes/$(theme)/gnome-shell $(DESTDIR)$(PREFIX)/share/gnome-shell/theme/$(theme);)
	mkdir -p $(DESTDIR)$(PREFIX)/share/gnome-shell/modes
	cp -a src/modes/* $(DESTDIR)$(PREFIX)/share/gnome-shell/modes/
	mkdir -p $(DESTDIR)$(PREFIX)/share/xsessions
	cp -a src/sessions/xsessions/* $(DESTDIR)$(PREFIX)/share/xsessions/
	mkdir -p $(DESTDIR)$(PREFIX)/share/wayland-sessions
	cp -a src/sessions/wayland-sessions/* $(DESTDIR)$(PREFIX)/share/wayland-sessions/
	ln -sf $(PREFIX)/share/themes/Flat-Remix/gnome-shell/assets/ $(DESTDIR)$(PREFIX)/share/gnome-shell/theme/assets

	# skip replacing gnome's theme when packaging
	$(if $(DESTDIR),, $(MAKE) Flat-Remix)

$(THEMES):
ifeq ($(IS_UBUNTU), true)
	-ln -sf $(PREFIX)/share/themes/$@/gnome-shell/assets/ $(PREFIX)/share/gnome-shell/theme/assets
	-update-alternatives --install $(PREFIX)/share/gnome-shell/theme/gdm3.css gdm3.css $(PREFIX)/share/themes/$@/gnome-shell/gnome-shell.css 100
else
	-mv -n $(PREFIX)/share/gnome-shell/gnome-shell-theme.gresource $(PREFIX)/share/gnome-shell/gnome-shell-theme.gresource.old
	-ln -sf $(PREFIX)/share/themes/$@/gnome-shell-theme.gresource $(PREFIX)/share/gnome-shell/gnome-shell-theme.gresource
endif

uninstall:
	-rm -rf $(foreach theme, $(THEMES), $(PREFIX)/share/themes/$(theme))
	-rm -rf $(foreach theme, $(THEMES) assets, $(PREFIX)/share/gnome-shell/theme/$(theme))
	-rm -rf $(PREFIX)/share/gnome-shell/modes/flat-remix*.json
	-rm -rf $(PREFIX)/share/xsessions/??_flat-remix*.desktop
	-rm -rf $(PREFIX)/share/wayland-sessions/??_flat-remix*.desktop
ifeq ($(IS_UBUNTU), true)
	-$(foreach theme, $(THEMES), update-alternatives --remove gdm3.css /usr/share/themes/$(theme)/gnome-shell/gnome-shell.css 2> /dev/null;)
	-update-alternatives --auto gdm3.css
else
	-mv $(PREFIX)/share/gnome-shell/gnome-shell-theme.gresource.old $(PREFIX)/share/gnome-shell/gnome-shell-theme.gresource
endif

_get_version:
	$(eval VERSION ?= $(shell git show -s --format=%cd --date=format:%Y%m%d HEAD))
	@echo $(VERSION)

_get_tag:
	$(eval TAG := $(shell git describe --abbrev=0 --tags))
	@echo $(TAG)

dist: _get_version
	git archive --format=tar.gz -o $(notdir $(CURDIR))-$(VERSION).tar.gz master -- $(THEMES)

release: _get_version
	$(MAKE) generate_changelog VERSION=$(VERSION)
	$(MAKE) aur_release VERSION=$(VERSION)
	$(MAKE) copr_release VERSION=$(VERSION)
	$(MAKE) launchpad_release
	git tag -f $(VERSION)
	git push origin --tags

aur_release: _get_version _get_tag
	cd aur; \
	sed "s/$(TAG)/$(VERSION)/g" -i PKGBUILD .SRCINFO; \
	git commit -a -m "$(VERSION)"; \
	git push origin master;

	git commit aur -m "Update aur version $(VERSION)"
	git push origin master

copr_release: _get_version _get_tag
	sed "s/$(TAG)/$(VERSION)/g" -i $(PKGNAME).spec
	git commit $(PKGNAME).spec -m "Update $(PKGNAME).spec version $(VERSION)"
	git push origin master

launchpad_release: _get_version
	cp -a Flat-Remix* src Makefile deb/$(PKGNAME)
	sed "s/{}/$(VERSION)/g" -i deb/$(PKGNAME)/debian/changelog-template
	cd deb/$(PKGNAME)/debian/ && echo " -- $(MAINTAINER)  $$(date -R)" | cat changelog-template - > changelog
	cd deb/$(PKGNAME) && debuild -S -d
	dput ppa deb/$(PKGNAME)_$(VERSION)_source.changes
	git checkout deb
	git clean -df deb

undo_release: _get_tag
	-git tag -d $(TAG)
	-git push --delete origin $(TAG)

generate_changelog: _get_version _get_tag
	git checkout $(TAG) CHANGELOG
	echo [$(VERSION)] > /tmp/out
	git log --pretty=format:' * %s' $(TAG)..HEAD >> /tmp/out
	echo >> /tmp/out
	echo | cat - CHANGELOG >> /tmp/out
	mv /tmp/out CHANGELOG
	$$EDITOR CHANGELOG
	git commit CHANGELOG -m "Update CHANGELOG version $(VERSION)"
	git push origin master


.PHONY: $(THEMES) all build install uninstall _get_version _get_tag dist release aur_release copr_release launchpad_release undo_release generate_changelog

# .BEGIN is ignored by GNU make so we can use it as a guard
.BEGIN:
	@head -3 Makefile
	@false
