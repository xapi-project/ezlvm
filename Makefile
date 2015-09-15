COMMANDS=Plugin.Query Plugin.diagnostics SR.create SR.ls SR.destroy SR.attach SR.stat SR.detach Volume.create Volume.destroy Volume.stat Volume.snapshot Volume.clone Volume.set_name Volume.set_description
LIBRARIES=lvm.ml common.ml

.PHONY: clean
clean:
	rm -f *.exe

.PHONY: test
test:
	# Running the commands will invoke the typechecker
	for command in $(COMMANDS); do \
	        echo $$command ; \
		(cd src/; ./$$command --test) ; \
	done

DESTDIR?=/
SCRIPTDIR?=/usr/libexec/xapi-storage-script

.PHONY: install
install:
	mkdir -p $(DESTDIR)$(SCRIPTDIR)/volume/org.xen.xapi.storage.ezlvm
	(cd src; install -m 0755 $(COMMANDS) $(DESTDIR)$(SCRIPTDIR)/volume/org.xen.xapi.storage.ezlvm)
	(cd src; install -m 0644 $(LIBRARIES) $(DESTDIR)$(SCRIPTDIR)/volume/org.xen.xapi.storage.ezlvm)
