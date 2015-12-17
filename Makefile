PROJECT = rabbitmq_test

BUILD_DEPS = rabbitmq_codegen
DEPS = amqp_client rabbitmq_java_client meck

ifneq ($(IS_DEP),1)
# Include rabbit as a dependency when the testsuite is started from this
# project. However, do not include it when the testsuite is started from
# rabbit itself.
TEST_DEPS += rabbit
endif

DEP_PLUGINS = rabbit_common/mk/rabbitmq-run.mk \
	      rabbit_common/mk/rabbitmq-tests.mk \
	      rabbit_common/mk/rabbitmq-tools.mk

# FIXME: Use erlang.mk patched for RabbitMQ, while waiting for PRs to be
# reviewed and merged.

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk
include erlang.mk

TEST_RABBIT_PORT=5672
TEST_HARE_PORT=5673
TEST_RABBIT_SSL_PORT=5671
TEST_HARE_SSL_PORT=5670

FILTER ?= all
COVER ?= true

ifeq ($(COVER), true)
COVER_START = start-cover
COVER_STOP = stop-cover
endif

WITH_BROKER_TEST_COMMANDS := rabbit_test_runner:run_in_broker(\"$(CURDIR)/test\",\"$(FILTER)\")

# This requires Erlang R15B+.
STANDALONE_TEST_COMMANDS := rabbit_test_runner:run_multi(\"$(DEPS_DIR)\",\"$(CURDIR)/test\",\"$(FILTER)\",$(COVER),none)

pre-standalone-tests:: test-tmpdir

RMQ_ERLC_OPTS := -Derlang_r15b_or_later

RMQ_ERLC_OPTS += -I $(DEPS_DIR)/rabbit_common/include \
		 -I $(RABBITMQ_BROKER_DIR)/include \
		 -pa $(RABBITMQ_BROKER_DIR)/ebin

ERLC_OPTS += $(RMQ_ERLC_OPTS)
TEST_ERLC_OPTS += $(RMQ_ERLC_OPTS)

# This requires Erlang R13B+.
SSL_VERIFY_OPTION :={verify,verify_peer},{fail_if_no_peer_cert,false}
export SSL_CERTS_DIR := $(realpath certs)
export PASSWORD := test
RABBIT_BROKER_OPTIONS := "-rabbit ssl_listeners [{\\\"0.0.0.0\\\",$(TEST_RABBIT_SSL_PORT)}] -rabbit ssl_options [{cacertfile,\\\"$(SSL_CERTS_DIR)/testca/cacert.pem\\\"},{certfile,\\\"$(SSL_CERTS_DIR)/server/cert.pem\\\"},{keyfile,\\\"$(SSL_CERTS_DIR)/server/key.pem\\\"},$(SSL_VERIFY_OPTION)] -rabbit auth_mechanisms ['PLAIN','AMQPLAIN','EXTERNAL','RABBIT-CR-DEMO']"
HARE_BROKER_OPTIONS := "-rabbit ssl_listeners [{\\\"0.0.0.0\\\",$(TEST_HARE_SSL_PORT)}] -rabbit ssl_options [{cacertfile,\\\"$(SSL_CERTS_DIR)/testca/cacert.pem\\\"},{certfile,\\\"$(SSL_CERTS_DIR)/server/cert.pem\\\"},{keyfile,\\\"$(SSL_CERTS_DIR)/server/key.pem\\\"},$(SSL_VERIFY_OPTION)] -rabbit auth_mechanisms ['PLAIN','AMQPLAIN','EXTERNAL','RABBIT-CR-DEMO']"

TESTS_FAILED := echo '\n============'\
	   	     '\nTESTS FAILED'\
		     '\n============\n'

TEST_EBIN_DIR = $(CURDIR)/test
JAVA_CLIENT_DIR = $(DEPS_DIR)/rabbitmq_java_client
RABBITMQ_TEST_DIR = $(CURDIR)
RABBITMQ_UMBRELLA_DIR = $(CURDIR)/../..
export RABBITMQ_TEST_DIR

tests:: full

full:
	$(test_verbose) OK=true && \
	$(MAKE) prepare && \
	trap '$(MAKE) cleanup' EXIT INT && \
	{ $(MAKE) run-tests || { OK=false; $(TESTS_FAILED); } } && \
	{ $(MAKE) run-lazy-vq-tests || { OK=false; $(TESTS_FAILED); } } && \
	{ $(MAKE) run-qpid-testsuite || { OK=false; $(TESTS_FAILED); } } && \
	{ ( cd $(JAVA_CLIENT_DIR) && MAKE=$(MAKE) $(ANT) $(ANT_FLAGS) test-suite ) || { OK=false; $(TESTS_FAILED); } } && \
	{ $$OK || $(TESTS_FAILED); } && $$OK

unit:
	$(test_verbose) OK=true && \
	$(MAKE) prepare && \
	trap '$(MAKE) cleanup' EXIT INT && \
	{ $(MAKE) run-tests || OK=false; } && \
	$$OK

lite:
	$(test_verbose) OK=true && \
	$(MAKE) prepare && \
	trap '$(MAKE) cleanup' EXIT INT && \
	{ $(MAKE) run-tests || OK=false; } && \
	{ ( cd $(JAVA_CLIENT_DIR) && MAKE=$(MAKE) $(ANT) $(ANT_FLAGS) test-suite ) || OK=false; } && \
	$$OK

conformance16:
	$(test_verbose) OK=true && \
	$(MAKE) prepare && \
	trap '$(MAKE) cleanup' EXIT INT && \
	{ $(MAKE) run-tests || OK=false; } && \
	{ ( cd $(JAVA_CLIENT_DIR) && MAKE=$(MAKE) $(ANT) $(ANT_FLAGS) test-suite ) || OK=false; } && \
	$$OK

lazy-vq-tests:
	$(test_verbose) OK=true && \
	$(MAKE) prepare && \
	trap '$(MAKE) cleanup' EXIT INT && \
	{ $(MAKE) run-lazy-vq-tests || OK=false; } && \
	$$OK

qpid_testsuite:
	$(verbose) $(MAKE) update-qpid-testsuite

update-qpid-testsuite:
	$(verbose) svn co -r 906960 http://svn.apache.org/repos/asf/qpid/trunk/qpid/python qpid_testsuite
	# hg clone http://rabbit-hg.eng.vmware.com/mirrors/qpid_testsuite

prepare-qpid-patch:
	$(verbose) cd qpid_testsuite && svn diff > ../qpid_patch && cd ..

run-qpid-testsuite: qpid_testsuite
	$(verbose) cd qpid_testsuite && svn revert -R .
	$(verbose) patch -N -r - -p0 -d qpid_testsuite/ < qpid_patch
	$(test_verbose) ! test -f $(RABBITMQ_UMBRELLA_DIR)/UMBRELLA.md || \
		AMQP_SPEC_DIR=$(RABBITMQ_UMBRELLA_DIR)/rabbitmq-docs/specs \
		AMQP_SPEC=$(RABBITMQ_UMBRELLA_DIR)/rabbitmq-docs/specs/amqp0-8.xml \
		qpid_testsuite/qpid-python-test -m tests_0-8 -I rabbit_failing.txt
	$(verbose) ! test -f $(RABBITMQ_UMBRELLA_DIR)/UMBRELLA.md || \
		AMQP_SPEC_DIR=$(RABBITMQ_UMBRELLA_DIR)/rabbitmq-docs/specs \
		AMQP_SPEC=$(RABBITMQ_UMBRELLA_DIR)/rabbitmq-docs/specs/amqp0-9-1.xml \
		qpid_testsuite/qpid-python-test -m tests_0-9 -I rabbit_failing.txt

clean:: clean-qpid-testsuite

clean-qpid-testsuite:
	$(gen_verbose) rm -rf qpid_testsuite

prepare: test-dist create_ssl_certs
	$(verbose) $(MAKE) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(HARE_BROKER_OPTIONS) \
		RABBITMQ_CONFIG_FILE=/does-not-exist \
		stop-node clean-node-db start-background-node start-rabbit-on-node \
		|| ($(MAKE) cleanup; false)
	$(verbose) $(MAKE) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(RABBIT_BROKER_OPTIONS) \
		RABBITMQ_CONFIG_FILE=/does-not-exist \
		stop-node clean-node-db start-background-node ${COVER_START} start-rabbit-on-node \
		|| ($(MAKE) cleanup; false)
	$(verbose) $(MAKE) RABBITMQ_NODENAME=hare stop-rabbit-on-node \
		|| ($(MAKE) cleanup; false)
# To determine the name of the remote node to join:
#   1. We use $(BASIC_SCRIPT_ENV_SETTINGS) to initialize the environment
#      used by the testsuite.
#   2. We source rabbitmq-env to get proper values for $RABBITMQ_NODENAME
#      and $RABBITMQ_NODE_TYPE.
#   3. We start a node with those informations to get the full node name
#      as computed by Erlang.
	$(verbose) $(RABBITMQCTL) -n hare join_cluster \
		$$($(BASIC_SCRIPT_ENV_SETTINGS); \
		. $(RABBITMQ_SCRIPTS_DIR)/rabbitmq-env && \
		erl -A0 -noinput -boot start_clean -hidden \
		 $$RABBITMQ_NAME_TYPE getname-$$$$-$$RABBITMQ_NODENAME \
		 -eval 'io:format("~s~n", [node()]), halt(0).' \
		 | sed s/^getname-$$$$-//) \
		|| ($(MAKE) cleanup; false)
	$(verbose) $(MAKE) RABBITMQ_NODENAME=hare start-rabbit-on-node \
		|| ($(MAKE) cleanup; false)

start-app:
	$(exec_verbose) $(MAKE) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(RABBIT_BROKER_OPTIONS) \
		RABBITMQ_CONFIG_FILE=/does-not-exist \
		start-rabbit-on-node

stop-app:
	$(exec_verbose) $(MAKE) stop-rabbit-on-node

restart-app: stop-app start-app

start-secondary-app:
	$(exec_verbose) $(MAKE) RABBITMQ_NODENAME=hare start-rabbit-on-node

stop-secondary-app:
	$(exec_verbose) $(MAKE) RABBITMQ_NODENAME=hare stop-rabbit-on-node

restart-secondary-node:
	$(exec_verbose) $(MAKE) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(HARE_BROKER_OPTIONS) \
		RABBITMQ_CONFIG_FILE=/does-not-exist \
		stop-node start-background-node
	$(verbose) $(MAKE) RABBITMQ_NODENAME=hare start-rabbit-on-node

force-snapshot:
	$(exec_verbose) $(MAKE) force-snapshot

enable-ha:
	$(exec_verbose) $(RABBITMQCTL) set_policy HA \
		".*" '{"ha-mode": "all"}'

disable-ha:
	$(exec_verbose) $(RABBITMQCTL) clear_policy HA

cleanup:
	-$(exec_verbose) $(MAKE) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(HARE_BROKER_OPTIONS) \
		RABBITMQ_CONFIG_FILE=/does-not-exist \
		stop-rabbit-on-node stop-node
	-$(verbose) $(MAKE) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(RABBIT_BROKER_OPTIONS) \
		RABBITMQ_CONFIG_FILE=/does-not-exist \
		stop-rabbit-on-node ${COVER_STOP} stop-node

# This requires Erlang R16B01+.
create_ssl_certs:
	$(gen_verbose) $(MAKE) -C certs DIR=$(SSL_CERTS_DIR) clean all
