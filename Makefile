CC ?= cc
AR ?= ar
CFLAGS ?= -std=c99 -Wall -Wextra -Wpedantic -O2
LDFLAGS ?=

BUILD_DIR := build
SRC := src/parser.c
HEADER := src/parser.h
CLI_SRC := src/main.c
LIB_NAME := flags2env
STATIC_LIB := $(BUILD_DIR)/lib$(LIB_NAME).a

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
SHARED_LIB := $(BUILD_DIR)/lib$(LIB_NAME).dylib
SHARED_FLAGS := -dynamiclib -Wl,-install_name,@rpath/lib$(LIB_NAME).dylib
else ifeq ($(OS),Windows_NT)
SHARED_LIB := $(BUILD_DIR)/$(LIB_NAME).dll
SHARED_FLAGS := -shared
else
SHARED_LIB := $(BUILD_DIR)/lib$(LIB_NAME).so
SHARED_FLAGS := -shared
endif

CLI := $(BUILD_DIR)/flags2env
PROCESS_SMOKE := $(BUILD_DIR)/process-smoke
API_HARDENING := $(BUILD_DIR)/api-hardening
PARSER_OBJ := $(BUILD_DIR)/parser.o

.PHONY: all borrow-check clean codegen-docker-test core-docker-test parity-test readme-test test shared static cli FORCE

FORCE:

all: shared static cli

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(PARSER_OBJ): $(SRC) $(HEADER) FORCE | $(BUILD_DIR)
	$(CC) $(CFLAGS) -fPIC -c $(SRC) -o $@

shared: $(SHARED_LIB)

$(SHARED_LIB): $(PARSER_OBJ)
	$(CC) $(SHARED_FLAGS) $(LDFLAGS) $< -o $@

static: $(STATIC_LIB)

$(STATIC_LIB): $(PARSER_OBJ)
	ZERO_AR_DATE=1 $(AR) rcs $@ $<

cli: $(CLI)

$(CLI): $(SRC) $(CLI_SRC) $(HEADER) FORCE | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SRC) $(CLI_SRC) -o $@

test: borrow-check readme-test parity-test $(PROCESS_SMOKE) $(API_HARDENING)
	./tests/run.sh
	$(API_HARDENING)
	$(PROCESS_SMOKE) --port 7777 -d

codegen-docker-test:
	./tests/codegen-docker/run.sh

core-docker-test:
	./tests/core-docker/run.sh

readme-test: ./scripts/test-readme-snippets.mjs
	./scripts/test-readme-snippets.mjs

parity-test: $(CLI)
	./tests/parity/run.sh

process-test: $(PROCESS_SMOKE)
	$(PROCESS_SMOKE) --port 7777 -d

borrow-check:
	./scripts/borrow-check.sh

$(PROCESS_SMOKE): $(SRC) tests/process_smoke.c $(HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc $(SRC) tests/process_smoke.c -o $@

$(API_HARDENING): $(SRC) tests/api_hardening.c $(HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc $(SRC) tests/api_hardening.c -o $@

clean:
	rm -rf $(BUILD_DIR)
