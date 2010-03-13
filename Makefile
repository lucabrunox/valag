VALAC = valac
SRCS = main.vala graphgenerator.vala
PREFIX = /usr/local
DESTDIR = $(PREFIX)

all: valag

valag: $(SRCS)
	$(VALAC) -o valag --pkg vala-1.0 --pkg libgvc --pkg glib-2.0 --vapidir . $+

install: valag
	install -c ./valag -D $(DESTDIR)/bin/valag

clean:
	rm -f valag *.c