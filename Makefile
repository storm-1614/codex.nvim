.PHONY: all check test

LUA_FILES := $(shell find lua plugin tests -type f -name '*.lua' | sort)
LUAC ?= luac

all: check test

check:
	$(LUAC) -p $(LUA_FILES)
	sh -n tests/run.sh

test:
	sh tests/run.sh
