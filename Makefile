PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
LIBDIR  ?= /usr/local/lib/rci-tor
DOCDIR  ?= $(PREFIX)/share/doc/rci-tor

.PHONY: install uninstall

install:
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 rci-tor $(DESTDIR)$(BINDIR)/rci-tor
	install -d $(DESTDIR)$(DOCDIR)
	install -m 0644 README.md $(DESTDIR)$(DOCDIR)/README.md
	@echo "rci-tor installed to $(DESTDIR)$(BINDIR)/rci-tor"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/rci-tor
	rm -rf $(DESTDIR)$(DOCDIR)
	@echo "rci-tor removed."