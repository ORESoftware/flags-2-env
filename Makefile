CC ?= cc
AR ?= ar
CFLAGS ?= -std=c99 -Wall -Wextra -Wpedantic -O2
LDFLAGS ?=

BUILD_DIR := build
SRC := src/parser.c
HEADER := src/parser.h
CONTEXT_SRC := src/terminal_context.c
CONTEXT_HEADER := src/terminal_context.h
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
ALLOCATION_FAILURE := $(BUILD_DIR)/allocation-failure
TERMINAL_CONTEXT_TEST := $(BUILD_DIR)/terminal-context-test
PARSER_OBJ := $(BUILD_DIR)/parser.o
CONTEXT_OBJ := $(BUILD_DIR)/terminal_context.o
LIB_OBJECTS := $(PARSER_OBJ) $(CONTEXT_OBJ)

.PHONY: all borrow-check clean codegen-docker-test core-docker-test formal-check parity-test readme-test test shared static cli FORCE

FORCE:

all: shared static cli

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(PARSER_OBJ): $(SRC) $(HEADER) FORCE | $(BUILD_DIR)
	$(CC) $(CFLAGS) -fPIC -c $(SRC) -o $@

$(CONTEXT_OBJ): $(CONTEXT_SRC) $(CONTEXT_HEADER) $(HEADER) FORCE | $(BUILD_DIR)
	$(CC) $(CFLAGS) -fPIC -c $(CONTEXT_SRC) -o $@

shared: $(SHARED_LIB)

$(SHARED_LIB): $(LIB_OBJECTS)
	$(CC) $(SHARED_FLAGS) $(LDFLAGS) $(LIB_OBJECTS) -o $@

static: $(STATIC_LIB)

$(STATIC_LIB): $(LIB_OBJECTS)
	ZERO_AR_DATE=1 $(AR) rcs $@ $(LIB_OBJECTS)

cli: $(CLI)

$(CLI): $(SRC) $(CONTEXT_SRC) $(CLI_SRC) $(HEADER) $(CONTEXT_HEADER) FORCE | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SRC) $(CONTEXT_SRC) $(CLI_SRC) -o $@

test: borrow-check readme-test parity-test $(PROCESS_SMOKE) $(API_HARDENING) $(ALLOCATION_FAILURE) $(TERMINAL_CONTEXT_TEST)
	./tests/run.sh
	$(API_HARDENING)
	$(ALLOCATION_FAILURE) tests/subcommands-deep/.cli-flags.toml
	$(TERMINAL_CONTEXT_TEST)
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

formal-check:
	./scripts/formal-check.sh

$(PROCESS_SMOKE): $(SRC) tests/process_smoke.c $(HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc $(SRC) tests/process_smoke.c -o $@

$(API_HARDENING): $(SRC) tests/api_hardening.c $(HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc $(SRC) tests/api_hardening.c -o $@

$(ALLOCATION_FAILURE): $(SRC) tests/allocation_failure.c $(HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc tests/allocation_failure.c -o $@

$(TERMINAL_CONTEXT_TEST): $(CONTEXT_SRC) $(CONTEXT_HEADER) $(HEADER) tests/terminal_context.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc $(CONTEXT_SRC) tests/terminal_context.c -o $@

clean:
	rm -rf $(BUILD_DIR)
