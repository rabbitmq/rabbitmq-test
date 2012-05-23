BROKER_DIR=$(abspath ../../../rabbitmq-server)
CLIENT_DIR=$(abspath ../../../rabbitmq-server)
HOST_SHORTNAME=$(shell hostname -s)
USER_SHORTNAME=$(shell whoami)
LIB_DIR=$(abspath lib)
BIN_DIR=$(abspath bin)
TEMP_DIRS=lib bin ebin

SOURCE_DIR=src
TEST_DIR=test
MAIN_SOURCES=$(wildcard $(SOURCE_DIR)/*.erl)
TEST_SOURCES=$(wildcard $(TEST_DIR)/*.erl)
TEST_SUITES=$(wildcard $(TEST_DIR)/*_SUITE.erl)

ifndef SUITES
SUITES=$(patsubst $(TEST_DIR)/%_SUITE.erl, %, $(TEST_SUITES))
endif

SOURCES=$(wildcard $(SOURCE_DIR)/*.erl)
SUPPORT_BEAMS=$(patsubst $(SOURCE_DIR)/%.erl, $(EBIN_DIR)/%.beam, $(SOURCES))
CT_LOGLEVEL ?= info

.PHONY: all
all: $(SUITES)

.PHONY: clean
clean: # TODO: tidy this up so it's generated not manually set up
    rm -dr lib
    rm -dr bin
    rm -dr log

.PHONY: lib bin
$(TEMP_DIRS): # TODO: don't create the directories unless they're missing
    mkdir -p $@

.PHONY: escripts
escripts: bin
escripts: bin/$(REBAR)

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
    ./bin/rebar -j7 skip_deps=true compile

# TODO: consider whether patching or generating config would be
# cleaner than maintaining 'rabbit' branches for these repos
bin/%:
   git clone -b rabbit https://github.com/hyperthunk/$*.git $*
   PATH="$(BIN_DIR):${PATH}" $(MAKE) -C $*
   cp $*/$* bin/
