SUBDIRS=volume

.PHONY: clean
clean:
	for dir in $(SUBDIRS); do \
          $(MAKE) -C $$dir clean; \
        done

.PHONY: test
test:
	for dir in $(SUBDIRS); do \
          $(MAKE) -C $$dir test; \
        done
