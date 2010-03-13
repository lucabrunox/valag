VALAC = valac
SRCS = main.vala graphgenerator.vala
PREFIX = /usr/local
DESTDIR = $(PREFIX)

all: valag

valag: $(SRCS)
	valac -o valag --pkg vala-1.0 --pkg libgvc --vapidir . $+

install: valag
	install -c ./valag -D $(DESTDIR)/bin/valag
