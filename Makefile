VALAC = valac
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