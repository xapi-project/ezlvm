COMMANDS=Plugin.Query Plugin.diagnostics SR.create SR.ls SR.destroy SR.attach SR.detach Volume.create Volume.destroy Volume.stat

.PHONY: clean
clean:
	rm -f *.exe

.PHONY: test
test:
	# Running the commands will invoke the typechecker
	for command in $(COMMANDS); do \
	        echo $$command ; \
		./$$command --test ; \
	done
