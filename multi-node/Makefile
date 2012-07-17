# NB: VERSION *might* be passed down from another makefile, otherwise we
# will take it from the user - in CI in seems this will always be 0.0.0 
VERSION ?= 0.0.0
BROKER_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-server)
CLIENT_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client)
COMMON_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client/deps/rabbit_common-$(VERSION))
COMMON_SRC=$(COMMON_DIR)/src
LIB_DIR=$(abspath lib)
BIN_DIR=$(abspath bin)
TEMP_DIRS=lib test-lib bin ebin test-ebin
AMQP_CLIENT=$(CLIENT_DIR)/dist/amqp_client-$(VERSION)
RABBIT_SERVER=$(abspath lib/rabbit)
REBAR=bin/rebar
SYSTEST=test-lib/systest/priv/bin/systest
SYSTEST_LIB=test-lib/systest
TESTLIBS=$(AMQP_CLIENT) $(RABBIT_SERVER) $(RABBIT_COMMON) $(SYSTEST_LIB)
REBAR_LOG ?= "0"
SYSTEST_VERSION=v0.7.10
SYSTEST_VERBOSE ?= 'false'
SYSTEST_DUMP ?= 'false'
SYSTEST_LOGGING ?= 'false'
SYSTEST_PROFILE ?= ''

ifneq ($(SYSTEST_LOGGING), 'false')
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
all: test-all

.PHONY: clean
clean:
	rm -rf $(TEMP_DIRS)

$(TEMP_DIRS):
	mkdir -p $@

.PHONY: test-all
test-all: $(SYSTEST) test-compile
	ERL_LIBS="$(CLIENT_DIR)/dist:lib:${ERL_LIBS}" \
	ERL_FLAGS="-pa lib -pa ebin -pa $(RABBIT_SERVER)/ebin -pz $(CLIENT_DIR)/dist/amqp_client/ebin -pa test-ebin" \
	RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
		$(SYSTEST) $(NOISE) $(OPERATOR_LOG) $(DUMP) \
			--cover-dir=ebin \
			--cover-dir=$(RABBIT_SERVER)/ebin \
			--cover-dir=$(AMQP_CLIENT)/ebin

.PHONY: test-profile
ifneq ($(SYSTEST_PROFILE), '')
test-profile: $(SYSTEST) test-compile
	ERL_LIBS="$(CLIENT_DIR)/dist:lib:${ERL_LIBS}" \
	ERL_FLAGS="-pa lib -pa ebin -pa $(RABBIT_SERVER)/ebin -pz $(CLIENT_DIR)/dist/amqp_client/ebin -pa test-ebin" \
	RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
		$(SYSTEST) -P $(SYSTEST_PROFILE) $(NOISE) $(OPERATOR_LOG) $(DUMP) \
			--cover-dir=ebin \
			--cover-dir=$(RABBIT_SERVER)/ebin \
			--cover-dir=$(AMQP_CLIENT)/ebin
else
test-profile:
	$(error you need to specify a SYSTEST_PROFILE to run this target)
endif

.PHONY: test-compile
test-compile: $(REBAR) $(RABBIT_SERVER) test-ebin
	ERL_LIBS="$(CLIENT_DIR)/dist:lib:${ERL_LIBS}" \
		$(REBAR) -C systest.config skip_deps=true compile -v $(REBAR_LOG)
	cp -R ebin test-ebin

$(RABBIT_SERVER): $(CLIENT_DIR)/dist lib
	ln -fs $(BROKER_DIR) $@

$(CLIENT_DIR)/dist:
	$(MAKE) -C $(CLIENT_DIR)

test-lib/%: test-lib
	git clone https://github.com/nebularis/$*.git test-lib/$*
	git --git-dir=test-lib/$*/.git \
		--work-tree=test-lib/$* \
		checkout $(SYSTEST_VERSION)

$(SYSTEST): $(SYSTEST_LIB)
	PATH="bin:${PATH}" $(MAKE) -C test-lib/systest

bin/%: bin $(SYSTEST_LIB)
	cp test-lib/systest/bin/$* bin/$*

