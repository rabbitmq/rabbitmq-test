BROKER_DIR=$(abspath ../../rabbitmq-server)
CLIENT_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client)
COMMON_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client/deps/rabbit_common-0.0.0)
COMMON_SRC=$(COMMON_DIR)/src
LIB_DIR=$(abspath lib)
BIN_DIR=$(abspath bin)
TEMP_DIRS=lib bin ebin
AMQP_CLIENT=lib/amqp_client
RABBIT_COMMON=lib/rabbit_common
RABBIT_SERVER=lib/rabbit
TESTLIBS=$(AMQP_CLIENT) $(RABBIT_SERVER) $(RABBIT_COMMON)
SYSTEST=bin/systest
SYSTEST_URI="https://github.com/downloads/nebularis/systest/systest"
SYSTEST_VERSION="0.5.4"
LOGLEVEL ?= "2"

.PHONY: all
all: $(SUITES)

.PHONY: clean
clean: clean-logs
	rm -rf bin ebin lib

.PHONY: clean-logs
clean-logs:
	rm -rf logs

$(TEMP_DIRS):
	mkdir -p $@

.PHONY: ha-test
ha-test: bin bin/systest lib $(TESTLIBS) $(COMMON_SRC)
	ERL_FLAGS="-pa lib -pa ebin -pa $(BROKER_DIR)/ebin" \
	RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
	$(SYSTEST) -C -v $(LOGLEVEL)

.PHONY: test-compile
test-compile: $(SYSTEST)
	$(SYSTEST) -C -n

$(AMQP_CLIENT):
	ln -fs $(CLIENT_DIR) $@

$(RABBIT_COMMON):
	ln -fs $(COMMON_DIR) $@

$(COMMON_SRC):
	cp -R $(RABBIT_SERVER)/src $(RABBIT_COMMON)

$(RABBIT_SERVER):
	ln -fs $(BROKER_DIR) $@

bin/%:
	mkdir -p bin
	curl -L $(SYSTEST_URI)-$(SYSTEST_VERSION)-SNAPSHOT > $@
	chmod +x $@
