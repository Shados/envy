# Executables used in the build process
MOON?=moon
MOONC?=moonc

# Directories
MANUAL_DIR=manual
MANUAL_SRC=$(MANUAL_DIR)/src
# TODO read in from the book.toml?
MANUAL_BUILD_DIR=docs
MOON_DIR=moon
LUA_OUT_DIR=lua

# Files
MANUAL_SRC_FILES:=$(wildcard $(MANUAL_SRC)/*.md)
MOON_FILES:=$(shell find $(MOON_DIR) -name '*.moon' -type f)
LUA_FILES:=$(patsubst moon/%,lua/%,$(patsubst %.moon,%.lua,$(MOON_FILES)))

.PHONY: all clean book-watch

all: $(MANUAL_BUILD_DIR) $(LUA_FILES)

clean:
	rm -rf $(LUA_FILES) && \
	cd $(MANUAL_DIR) && \
	mdbook clean

$(MANUAL_BUILD_DIR): $(MANUAL_SRC_FILES)
	cd $(MANUAL_DIR) && \
	mdbook build

book-watch: $(MANUAL_SRC_FILES)
	cd $(MANUAL_DIR) && \
	mdbook watch -o

manual/src/options.md: manual/options-builder.moon options.sha256
	@echo "Regenerating options"
	$(MOON) manual/options-builder.moon $(optionsFile) $@

# Shenanigans to trigger rebuild of manual/options.md every time the Nix-built
# options JSON changes
options.sha256: FORCE
	@$(if $(filter-out $(shell cat $@ 2>/dev/null),$(shell sha256sum $(optionsFile))),sha256sum $(optionsFile) > $@)

FORCE:

lua/%.lua: moon/%.moon
	@test -d $(@D) || mkdir -pm 755 $(@D)
	$(MOONC) -o $@ $<
