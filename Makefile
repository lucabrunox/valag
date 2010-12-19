NULL =

VALAC = valac
VERSION = 1.1
SRCS = main.vala graphgenerator.vala flowgraphgenerator.vala
PREFIX = /usr/local
DESTDIR = $(PREFIX)

all: valag

valag: $(SRCS)
	$(VALAC) -g -o valag --thread --pkg libvala-0.12 --pkg libgvc --pkg glib-2.0 --vapidir . $+

install: valag
	install -c ./valag -D $(DESTDIR)/bin/valag

clean:
	rm -f valag *.c

DISTFILES = \
	AUTHORS \
	COPYING \
	COPYING.LESSER \
	ChangeLog \
	Makefile \
	NEWS \
	README \
	flowgraphgenerator.vala \
	gitlog-to-changelog \
	graphgenerator.vala \
	libgvc.vapi \
	main.vala \
	xdot.py \
	$(NULL)

ChangeLog:
	./gitlog-to-changelog > ChangeLog

dist: $(DISTFILES)
	mkdir valag-$(VERSION)
	cp -rf $(DISTFILES) valag-$(VERSION)
	tar -czf valag-$(VERSION).tar.gz valag-$(VERSION)
	rm -rf valag-$(VERSION)

.PHONY: install clean dist
