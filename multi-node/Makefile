# NB: VERSION *might* be passed down from another makefile, otherwise we
# will take it from the user - in CI in seems this will always be 0.0.0 
VERSION ?= 0.0.0
BROKER_DIR=$(abspath ../../rabbitmq-server)
CLIENT_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client)
COMMON_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client/deps/rabbit_common-$(VERSION))
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
REBAR_LOG ?= "0"
SYSTEST_VERSION=v0.7.5
SYSTEST_VERBOSE ?= 'false'
SYSTEST_DUMP ?= 'false'
SYSTEST_LOG ?= 'false'
SYSTEST_PROFILE ?= ''

ifneq ($(SYSTEST_LOG), 'false')
OPERATOR_LOG=-L operator
else
OPERATOR_LOG=
endif

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

.PHONY: test-all
test-all: $(SYSTEST) test-compile
	ERL_FLAGS="-pa lib -pa ebin -pa $(BROKER_DIR)/ebin -pa test-ebin" \
	RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
		$(SYSTEST) $(NOISE) $(OPERATOR_LOG) $(DUMP) \
			--cover-dir=ebin \
			--cover-dir=$(BROKER_DIR)/ebin \
			--cover-dir=$(CLIENT_DIR)/ebin

.PHONY: dry-run
ifneq ($(SYSTEST_PROFILE), '')
dry-run: $(SYSTEST) test-compile
	$(info test libraries: $(TESTLIBS))
	$(info $(shell $(REBAR) -V))
	ERL_FLAGS="-pa lib -pa ebin -pa $(BROKER_DIR)/ebin -pa test-ebin" \
		$(SYSTEST) -P $(SYSTEST_PROFILE) -n
else
dry-run:
	$(info set the SYSTEST_PROFILE variable in order to do a dry run)
endif

.PHONY: ha-test
ha-test: $(SYSTEST) test-compile
	ERL_FLAGS="-pa lib -pa ebin -pa $(BROKER_DIR)/ebin -pa test-ebin" \
	RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
		$(SYSTEST) -P $@ $(NOISE) $(OPERATOR_LOG) $(DUMP) \
			--cover-dir=ebin \
			--cover-dir=$(BROKER_DIR)/ebin \
			--cover-dir=$(CLIENT_DIR)/ebin

.PHONY: test-compile
test-compile: $(REBAR) $(SYSTEST) $(TESTLIBS) $(COMMON_SRC) test-ebin
	$(REBAR) -C systest.config skip_deps=true compile -v $(REBAR_LOG)
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
	git clone -b stable https://github.com/nebularis/$*.git test-lib/$*
	git --git-dir=test-lib/$*/.git checkout $(SYSTEST_VERSION)

$(SYSTEST): $(SYSTEST_LIB)
	PATH="bin:${PATH}" $(MAKE) -C test-lib/systest

bin/%: bin
	git clone -b rabbit https://github.com/hyperthunk/$*.git lib/$*
	PATH="bin:${PATH}" $(MAKE) -C lib/$*
	cp lib/$*/$* bin/$*

