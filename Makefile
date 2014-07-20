COMMANDS=VDI.attach

.PHONY: clean
clean:
	rm *.exe

.PHONY: test
test:
	# Running the commands will invoke the typechecker
	for command in $(COMMANDS); do \
		./$$command --help ; \
	done
