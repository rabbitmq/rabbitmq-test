
BROKER_DIR=$(abspath ../../rabbitmq-server)
REBAR=rebar
RETEST=retest

ifndef SUITES
SUITES=$(shell cd inttest && find . -type d -mindepth 1 -print)
endif

HOST_SHORTNAME=$(shell hostname -s)
SCRATCH_DIR=$(abspath tmp)
BIN_DIR=$(abspath bin)
HELPER_EBIN=$(abspath ebin)
TEMP_DIRS=tmp bin ebin
SOURCE_DIR=src
EBIN_DIR=ebin
NODE_NAME=rabbit
SOURCES=$(wildcard $(SOURCE_DIR)/*.erl)
SUPPORT_BEAMS=$(patsubst $(SOURCE_DIR)/%.erl, $(EBIN_DIR)/%.beam, $(SOURCES))
RETEST_LOGLEVEL ?= info

RABBITMQ_NODENAME ?= rabbit
RABBITMQ_SERVER_START_ARGS ?=
RABBITMQ_MNESIA_DIR ?= $(TEMP_DIR)/rabbitmq-$(RABBITMQ_NODENAME)-mnesia
RABBITMQ_PLUGINS_EXPAND_DIR ?= $(TEMP_DIR)/rabbitmq-$(RABBITMQ_NODENAME)-plugins-scratch
RABBITMQ_LOG_BASE ?= $(TEMP_DIR)

.PHONY: all
all: $(SUITES)

.PHONY: clean
clean: # TODO: tidy this up so it's generated not manually set up
	rm -drf rebar
	rm -drf retest
	rm -drf bin
	rm -drf tmp
	rm -drf ebin
	rm -drf rt.work

.PHONY: tmp bin
$(TEMP_DIRS): # TODO: don't create the directories unless they're missing
	mkdir -p $@

.PHONY: escripts
escripts: bin
escripts: bin/$(REBAR)
escripts: bin/$(RETEST)

.PHONY: retest
retest: escripts tmp

.PHONY: reset	# make sure we've got a clean environment for each run...
	rm -drf tmp

.PHONY: helpers
helpers: ebin $(SUPPORT_BEAMS)

BASIC_SCRIPT_ENVIRONMENT_SETTINGS=\
	RABBITMQ_NODE_IP_ADDRESS="$(RABBITMQ_NODE_IP_ADDRESS)" \
	RABBITMQ_NODE_PORT="$(RABBITMQ_NODE_PORT)" \
	RABBITMQ_LOG_BASE="$(RABBITMQ_LOG_BASE)" \
	RABBITMQ_MNESIA_DIR="$(RABBITMQ_MNESIA_DIR)" \
	RABBITMQ_PLUGINS_EXPAND_DIR="$(RABBITMQ_PLUGINS_EXPAND_DIR)"

$(SUITES): reset helpers retest
		ERL_FLAGS="-pa $(HELPER_EBIN) -pa $(BROKER_DIR)/ebin" \
		RABBITMQ_SCRATCH_DIR=$(SCRATCH_DIR) \
		RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
		RABBITMQ_LOG_BASE=$(SCRATCH_DIR) \
		RABBITMQ_MNESIA_DIR=$(SCRATCH_DIR)/rabbitmq-rabbit-mnesia \
		RABBITMQ_PID_FILE=$(SCRATCH_DIR)/rabbitmq-rabbit-mnesia.pid \
		RABBITMQ_NODENAME=$(NODE_NAME) \
		RABBITMQ_PLUGINS_EXPAND_DIR=$(SCRATCH_DIR)/plugins \
		HOST_SHORTNAME=$(HOST_SHORTNAME) \
		bin/retest inttest/$@ -l $(RETEST_LOGLEVEL)

$(EBIN_DIR)/%.beam: $(SOURCE_DIR)/%.erl
	erlc -o ebin -pa $(BROKER_DIR)/ebin $<

# TODO: consider whether patching or generating config would be
# cleaner than maintaining 'rabbit' branches for these repos
bin/%:
	git clone -b rabbit https://github.com/hyperthunk/$*.git $*
	$(MAKE) -C $*
	cp $*/$* bin/

