# Executables used in the build process
MOONC?=moon

# Directories
MANUAL_DIR=manual
MANUAL_SRC=$(MANUAL_DIR)/src
MANUAL_BUILD=docs

# Files
MANUAL_SRC_FILES=$(wildcard $(MANUAL_SRC)/*.md)

.PHONY: all clean book-watch

all: book

clean:
	cd $(MANUAL_DIR) && \
	mdbook clean

book: $(MANUAL_SRC_FILES)
	cd $(MANUAL_DIR) && \
	mdbook build

book-watch: $(MANUAL_SRC_FILES)
	cd $(MANUAL_DIR) && \
	mdbook watch -o

manual/src/options.md: manual/options-builder.moon options.sha256
	@echo "Regenerating options"
	moon manual/options-builder.moon $(optionsFile) $@

# Shenanigans to trigger rebuild of manual/options.md every time the Nix-built
# options JSON changes
options.sha256: FORCE
	@$(if $(filter-out $(shell cat $@ 2>/dev/null),$(shell sha256sum $(optionsFile))),sha256sum $(optionsFile) > $@)

FORCE:
