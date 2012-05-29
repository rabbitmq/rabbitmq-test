BROKER_DIR=$(abspath ../../rabbitmq-server)
CLIENT_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client)
COMMON_DIR=$(abspath $(CLIENT_DIR)/deps/rabbit_common-0.0.0)
LIB_DIR=$(abspath lib)
BIN_DIR=$(abspath bin)
TEMP_DIRS=lib bin ebin
SYSTEST=lib/systest
AMQP_CLIENT=lib/amqp_client
RABBIT_COMMON=lib/rabbit_common
RABBIT_SERVER=lib/rabbit
TESTLIBS=$(AMQP_CLIENT) $(RABBIT_COMMON) $(RABBIT_SERVER)
REBAR=bin/rebar
LOGLEVEL ?= "4"

.PHONY: all
all: $(SUITES)

.PHONY: clean
clean:
	rm -dr bin ebin lib
	rm test/*.beam

.PHONY: lib bin
$(TEMP_DIRS): # TODO: don't create the directories unless they're missing
	mkdir -p $@

.PHONY: escripts
escripts: bin lib
escripts: $(REBAR)

BASIC_SCRIPT_ENVIRONMENT_SETTINGS=\
	RABBITMQ_NODE_IP_ADDRESS="$(RABBITMQ_NODE_IP_ADDRESS)" \
	RABBITMQ_NODE_PORT="$(RABBITMQ_NODE_PORT)" \
	RABBITMQ_LOG_BASE="$(RABBITMQ_LOG_BASE)" \
	RABBITMQ_MNESIA_DIR="$(RABBITMQ_MNESIA_DIR)" \
	RABBITMQ_PLUGINS_EXPAND_DIR="$(RABBITMQ_PLUGINS_EXPAND_DIR)"

.PHONY: ha-test
ha-test: $(SYSTEST) $(TESTLIBS)
	ERL_FLAGS="-pa lib/systest/ebin -pa $(BROKER_DIR)/ebin" \
	RABBITMQ_SCRATCH_DIR=$(SCRATCH_DIR) \
	RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
	RABBITMQ_LOG_BASE=$(SCRATCH_DIR) \
	RABBITMQ_MNESIA_DIR=$(SCRATCH_DIR)/rabbitmq-rabbit-mnesia \
	RABBITMQ_PID_FILE=$(SCRATCH_DIR)/rabbitmq-rabbit-mnesia.pid \
	RABBITMQ_PLUGINS_EXPAND_DIR=$(SCRATCH_DIR)/plugins \
	HOST_SHORTNAME=$(HOST_SHORTNAME) \
	$(REBAR) skip_deps=true -C test.config compile systest -v$(LOGLEVEL)

$(SYSTEST): escripts
	$(REBAR) -C dependencies.config -j7 get-deps compile -v$(LOGLEVEL)

.PHONY: $(AMQP_CLIENT)
$(AMQP_CLIENT):
	ln -s $(CLIENT_DIR) $@

.PHONY: $(RABBIT_COMMON)
$(RABBIT_COMMON):
	ln -s $(COMMON_DIR) $@

.PHONY: $(RABBIT_SERVER)
$(RABBIT_SERVER):
	ln -s $(BROKER_DIR) $@

# TODO: consider whether patching or generating config would be
# cleaner than maintaining 'rabbit' branches for these repos
bin/%:
	git clone -b rabbit https://github.com/hyperthunk/$*.git lib/$*
	PATH="$(BIN_DIR):${PATH}" $(MAKE) -C lib/$*
	cp lib/$*/$* bin/
