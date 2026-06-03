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
SHARED_FLAGS := -dynamiclib
else ifeq ($(OS),Windows_NT)
SHARED_LIB := $(BUILD_DIR)/$(LIB_NAME).dll
SHARED_FLAGS := -shared
else
SHARED_LIB := $(BUILD_DIR)/lib$(LIB_NAME).so
SHARED_FLAGS := -shared
endif

CLI := $(BUILD_DIR)/flags2env
PROCESS_SMOKE := $(BUILD_DIR)/process-smoke
PARSER_OBJ := $(BUILD_DIR)/parser.o

.PHONY: all borrow-check clean test shared static cli

all: shared static cli

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(PARSER_OBJ): $(SRC) $(HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -fPIC -c $(SRC) -o $@

shared: $(SHARED_LIB)

$(SHARED_LIB): $(PARSER_OBJ)
	$(CC) $(SHARED_FLAGS) $(LDFLAGS) $< -o $@

static: $(STATIC_LIB)

$(STATIC_LIB): $(PARSER_OBJ)
	$(AR) rcs $@ $<

cli: $(CLI)

$(CLI): $(SRC) $(CLI_SRC) $(HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(SRC) $(CLI_SRC) -o $@

test: borrow-check $(CLI) $(PROCESS_SMOKE)
	./tests/run.sh
	$(PROCESS_SMOKE) --port 7777 -d

process-test: $(PROCESS_SMOKE)
	$(PROCESS_SMOKE) --port 7777 -d

borrow-check:
	./scripts/borrow-check.sh

$(PROCESS_SMOKE): $(SRC) tests/process_smoke.c $(HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -Isrc $(SRC) tests/process_smoke.c -o $@

clean:
	rm -rf $(BUILD_DIR)
