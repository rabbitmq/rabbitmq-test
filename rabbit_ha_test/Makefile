BROKER_DIR=$(abspath ../../rabbitmq-server)
CLIENT_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client)
COMMON_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client/deps/rabbit_common-0.0.0)
LIB_DIR=$(abspath lib)
BIN_DIR=$(abspath bin)
TEMP_DIRS=lib bin ebin
AMQP_CLIENT=lib/amqp_client
RABBIT_COMMON=lib/rabbit_common
RABBIT_SERVER=lib/rabbit
TESTLIBS=$(AMQP_CLIENT) $(RABBIT_COMMON) $(RABBIT_SERVER)
SYSTEST=bin/systest
SYSTEST_URI="https://github.com/downloads/nebularis/systest/systest"
SYSTEST_VERSION="0.4.0"
LOGLEVEL ?= "2"

.PHONY: all
all: $(SUITES)

.PHONY: clean
clean: clean-logs
	rm -rf bin ebin lib

.PHONY: clean-logs
clean-logs:
	rm -rf logs

.PHONY: lib bin
$(TEMP_DIRS): # TODO: don't create the directories unless they're missing
	mkdir -p $@

BASIC_SCRIPT_ENVIRONMENT_SETTINGS=\
	RABBITMQ_NODE_IP_ADDRESS="$(RABBITMQ_NODE_IP_ADDRESS)" \
	RABBITMQ_NODE_PORT="$(RABBITMQ_NODE_PORT)" \
	RABBITMQ_LOG_BASE="$(RABBITMQ_LOG_BASE)" \
	RABBITMQ_MNESIA_DIR="$(RABBITMQ_MNESIA_DIR)" \
	RABBITMQ_PLUGINS_EXPAND_DIR="$(RABBITMQ_PLUGINS_EXPAND_DIR)"

.PHONY: ha-test
ha-test: bin/systest lib $(TESTLIBS)
	ERL_FLAGS="-pa lib -pa ebin -pa $(BROKER_DIR)/ebin" \
	RABBITMQ_SCRATCH_DIR=$(SCRATCH_DIR) \
	RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
	RABBITMQ_LOG_BASE=$(SCRATCH_DIR) \
	RABBITMQ_MNESIA_DIR=$(SCRATCH_DIR)/rabbitmq-rabbit-mnesia \
	RABBITMQ_PID_FILE=$(SCRATCH_DIR)/rabbitmq-rabbit-mnesia.pid \
	RABBITMQ_PLUGINS_EXPAND_DIR=$(SCRATCH_DIR)/plugins \
	HOST_SHORTNAME=$(HOST_SHORTNAME) \
	$(SYSTEST) -C -v $(LOGLEVEL)

.PHONY: test-compile
test-compile: $(SYSTEST)
	$(SYSTEST) -C -n

.PHONY: $(AMQP_CLIENT)
$(AMQP_CLIENT):
	ln -fs $(CLIENT_DIR) $@

.PHONY: $(RABBIT_COMMON)
$(RABBIT_COMMON):
	ln -fs $(COMMON_DIR) $@

.PHONY: $(RABBIT_SERVER)
$(RABBIT_SERVER):
	ln -fs $(BROKER_DIR) $@

bin/%: fetch-systest

.PHONY: fetch-systest
fetch-systest: bin
	curl -L $(SYSTEST_URI)-$(SYSTEST_VERSION)-SNAPSHOT > bin/systest
	chmod +x bin/systest
