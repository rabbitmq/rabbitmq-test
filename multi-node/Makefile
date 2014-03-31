# NB: VERSION *might* be passed down from another makefile, otherwise we
# will take it from the user - in CI in seems this will always be 0.0.0 
VERSION ?= 0.0.0
UMBRELLA_DIR=$(abspath ../../)
BROKER_DIR=$(abspath ../../rabbitmq-server)
CLIENT_DIR=$(abspath ../../rabbitmq-erlang-client)
TEMP_DIRS=lib test-lib bin ebin test-ebin test/data
RABBIT_SERVER=$(abspath lib/rabbit)
RABBIT_PLUGINS=$(RABBIT_SERVER)/plugins
PLUGINS_SRC=$(abspath ../../rabbitmq-server/plugins-src)
REBAR=bin/rebar
SYSTEST=test-lib/systest/priv/bin/systest
SYSTEST_GIT=test-lib/systest
REBAR_LOG ?= "0"
SYSTEST_VERSION=v0.8.8
SYSTEST_VERBOSE ?= 'false'
SYSTEST_DUMP ?= 'false'
SYSTEST_LOGGING ?= 'false'
SYSTEST_NO_COVER ?= 'false'
SYSTEST_PROFILE ?= ''
SYSTEST_TARGET ?= ''
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
	PACKAGE_DIR=`pwd` \
		$(SYSTEST) $(SYSTEST_QUIET) $(NOISE) $(OPERATOR_LOG) $(DUMP) $(1) $(SYSTEST_COVER) $(EXTRA_FLAGS)
endef

.PHONY: all
all: test-all

.PHONY: clean
clean:
	rm -f $(PLUGINS_SRC)
	rm -rf $(TEMP_DIRS)

$(TEMP_DIRS):
	mkdir -p $@

.PHONY: test-all
# Cover seems to reliably hang multi_node_deaths_SUITE
test-all: $(SYSTEST) test-compile
	$(MAKE) -C . test-profile SYSTEST_PROFILE=ha-test
	$(MAKE) -C . test-profile SYSTEST_PROFILE=kill-multi SYSTEST_NO_COVER=1

.PHONY: test-profile
.PHONY: test-run
.PHONY: test-shell
ifneq ($(SYSTEST_PROFILE), '')
test-profile: $(SYSTEST) test-compile
	$(call systest,-P $(SYSTEST_PROFILE))
else
test-profile:
	$(error you need to specify a SYSTEST_PROFILE to run this target)
endif

ifneq ($(SYSTEST_TARGET), '')
test-run: $(SYSTEST) test-compile
	$(call systest,-Z $(SYSTEST_TARGET))

test-shell: $(SYSTEST) test-compile
	$(call systest,-P $(SYSTEST_PROFILE) -s -z $(SYSTEST_TARGET))
else
test-run:
	$(error you need to also specify SYSTEST_TARGET to run this target)

test-shell:
	$(error you need to set SYSTEST_TARGET to the sut/config name to run this target)
endif

.PHONY: test-compile
test-compile: $(REBAR) $(RABBIT_SERVER) $(RABBIT_PLUGINS) test-ebin
	ERL_LIBS="$(CLIENT_DIR)/dist:lib:${ERL_LIBS}" \
		$(REBAR) -C systest.config skip_deps=true compile -v $(REBAR_LOG)
	cp -R ebin test-ebin
	rm $(PLUGINS_SRC)

$(RABBIT_SERVER): $(CLIENT_DIR)/dist lib
	ln -fs $(BROKER_DIR) $@

$(RABBIT_PLUGINS): $(RABBIT_SERVER) $(PLUGINS_SRC)
	make -C $(RABBIT_SERVER)

$(PLUGINS_SRC):
	ln -fs $(UMBRELLA_DIR) $@

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

