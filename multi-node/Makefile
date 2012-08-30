# NB: VERSION *might* be passed down from another makefile, otherwise we
# will take it from the user - in CI in seems this will always be 0.0.0 
VERSION ?= 0.0.0
BROKER_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-server)
CLIENT_DIR=$(abspath ../../rabbitmq-public-umbrella/rabbitmq-erlang-client)
TEMP_DIRS=lib test-lib bin ebin test-ebin
RABBIT_SERVER=$(abspath lib/rabbit)
REBAR=bin/rebar
SYSTEST=test-lib/systest/priv/bin/systest
SYSTEST_GIT=test-lib/systest
REBAR_LOG ?= "0"
SYSTEST_VERSION=v0.8.2
SYSTEST_VERBOSE ?= 'false'
SYSTEST_DUMP ?= 'false'
SYSTEST_LOGGING ?= 'false'
SYSTEST_NO_COVER ?= 'false'
SYSTEST_PROFILE ?= ''
SYSTEST_EXTRA ?= ''

ifneq (,$(findstring s,$(MAKEFLAGS)))
SYSTEST_QUIET=-q
else
SYSTEST_QUIET=
endif

ifneq ($(SYSTEST_LOGGING), 'false')
OPERATOR_LOG=-L operator
SYSTEST_QUIET=
else
OPERATOR_LOG=
endif

ifneq ($(SYSTEST_VERBOSE), 'false')
NOISE=-L framework -L sut -L process
SYSTEST_QUIET=
else
NOISE=
endif

ifneq ($(SYSTEST_DUMP), 'false')
DUMP=-X
else
DUMP=
endif

ifneq ($(SYSTEST_EXTRA), '')
EXTRA_FLAGS=$(SYSTEST_EXTRA)
else
EXTRA_FLAGS=
endif

ifneq ($(SYSTEST_NO_COVER), 'false')
SYSTEST_COVER=-w
else
SYSTEST_COVER=--cover-dir=ebin \
			  --cover-dir=$(RABBIT_SERVER)/ebin \
			  --cover-dir=$(CLIENT_DIR)/ebin
endif

define systest
	ERL_LIBS="$(CLIENT_DIR)/dist:lib:${ERL_LIBS}" \
	ERL_FLAGS="-pa lib -pa ebin -pa $(RABBIT_SERVER)/ebin -pz $(CLIENT_DIR)/dist/amqp_client/ebin -pa test-ebin" \
	RABBITMQ_BROKER_DIR=$(BROKER_DIR) \
		$(SYSTEST) $(SYSTEST_QUIET) $(NOISE) $(OPERATOR_LOG) $(DUMP) $(1) $(SYSTEST_COVER) $(EXTRA_FLAGS)
endef

.PHONY: all
all: test-all

.PHONY: clean
clean:
	rm -rf $(TEMP_DIRS)

$(TEMP_DIRS):
	mkdir -p $@

.PHONY: test-all
test-all: $(SYSTEST) test-compile
	$(call systest,'')

.PHONY: test-profile
ifneq ($(SYSTEST_PROFILE), '')
test-profile: $(SYSTEST) test-compile
	$(call systest,-P $(SYSTEST_PROFILE))
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

.PHONY: systest-lib
systest-lib: $(SYSTEST_GIT)
	touch $(SYSTEST_GIT)/.done

$(SYSTEST_GIT):
	mkdir -p test-lib
	git clone -b stable https://github.com/nebularis/systest.git test-lib/systest
	git --git-dir=test-lib/systest/.git \
		--work-tree=test-lib/systest \
		checkout $(SYSTEST_VERSION)

$(SYSTEST): systest-lib
	PATH="bin:${PATH}" $(MAKE) -C test-lib/systest

bin/%: bin systest-lib
	cp test-lib/systest/bin/$* bin/$*


