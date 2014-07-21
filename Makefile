COMMANDS=SR.create SR.scan VDI.create VDI.destroy VDI.attach VDI.detach SR.destroy

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
