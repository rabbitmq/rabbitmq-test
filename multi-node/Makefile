BROKER_DIR=$(abspath ../../rabbitmq-server)
CLIENT_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client)
COMMON_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client/deps/rabbit_common-0.0.0)
COMMON_SRC=$(COMMON_DIR)/src
LIB_DIR=$(abspath lib)
BIN_DIR=$(abspath bin)
TEMP_DIRS=lib test-lib bin ebin test-ebin
AMQP_CLIENT=lib/amqp_client
RABBIT_COMMON=lib/rabbit_common
RABBIT_SERVER=lib/rabbit
REBAR=bin/rebar
SYSTEST=test-lib/systest/priv/bin/systest
SYSTEST_LIB=test-lib/systest
TESTLIBS=$(AMQP_CLIENT) $(RABBIT_SERVER) $(RABBIT_COMMON) $(SYSTEST_LIB)
SYSTEST_VERSION="0.7.0"
LOGLEVEL ?= "0"
SYSTEST_VERBOSE ?= 'false'
SYSTEST_DUMP ?= 'false'

ifneq ($(SYSTEST_VERBOSE), 'false')
NOISE=-L framework -L sut -L process
else
NOISE=
endif

ifneq ($(SYSTEST_DUMP), 'false')
DUMP=-X
else
DUMP=
endif

.PHONY: all
all: $(SUITES)

.PHONY: clean
clean: clean-logs
	rm -rf $(TEMP_DIRS)

.PHONY: clean-logs
clean-logs:
	rm -rf logs

$(TEMP_DIRS):
	mkdir -p $@

.PHONY: ha-test
ha-test: $(SYSTEST) test-compile
	ERL_FLAGS="-pa lib -pa ebin -pa $(BROKER_DIR)/ebin -pa test-ebin" \
	RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
		$(SYSTEST) -P $@ $(NOISE) $(DUMP)

.PHONY: test-compile
test-compile: $(REBAR) $(SYSTEST) $(TESTLIBS) $(COMMON_SRC) test-ebin
	$(REBAR) -C systest.config skip_deps=true compile -v $(LOGLEVEL)
	cp -R ebin test-ebin

$(AMQP_CLIENT):
	ln -fs $(CLIENT_DIR) $@

$(RABBIT_COMMON):
	ln -fs $(COMMON_DIR) $@

# NB: the cover server needs sources for rabbit_common too,
# so we copy the broker's sources across so it can find them
$(COMMON_SRC):
	cp -R $(RABBIT_SERVER)/src $(RABBIT_COMMON)

$(RABBIT_SERVER):
	ln -fs $(BROKER_DIR) $@

test-lib/%: test-lib
	git clone https://github.com/nebularis/$*.git test-lib/$*

$(SYSTEST): $(SYSTEST_LIB)
	PATH="bin:${PATH}" $(MAKE) -C test-lib/systest

bin/%: bin
	git clone -b rabbit https://github.com/hyperthunk/$*.git lib/$*
	PATH="bin:${PATH}" $(MAKE) -C lib/$*
	cp lib/$*/$* bin/$*

