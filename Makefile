PROJECT = rabbitmq_test

DEPS = amqp_client
TEST_DEPS = rabbit rabbitmq_codegen rabbitmq_java_client

DEP_PLUGINS = rabbit_common/mk/rabbitmq-tests.mk

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

RMQ_ERLC_OPTS += -I $(DEPS_DIR)/rabbit_common/include -I $(DEPS_DIR)/rabbit/include

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

BROKER_DIR = $(DEPS_DIR)/rabbit
TEST_EBIN_DIR = $(CURDIR)/test
JAVA_CLIENT_DIR = $(DEPS_DIR)/rabbitmq_java_client
RABBITMQ_TEST_DIR = $(CURDIR)
export RABBITMQ_TEST_DIR

tests:: full

full: test-dist
	$(test_verbose) OK=true && \
	$(MAKE) prepare && \
	{ $(MAKE) run-tests || { OK=false; $(TESTS_FAILED); } } && \
	{ $(MAKE) run-qpid-testsuite || { OK=false; $(TESTS_FAILED); } } && \
	{ ( cd $(JAVA_CLIENT_DIR) && MAKE=$(MAKE) $(ANT) $(ANT_FLAGS) test-suite ) || { OK=false; $(TESTS_FAILED); } } && \
	$(MAKE) cleanup && { $$OK || $(TESTS_FAILED); } && $$OK

unit: test-dist
	$(test_verbose) OK=true && \
	$(MAKE) prepare && \
	{ $(MAKE) run-tests || OK=false; } && \
	$(MAKE) cleanup && $$OK

lite: test-dist
	$(test_verbose) OK=true && \
	$(MAKE) prepare && \
	{ $(MAKE) run-tests || OK=false; } && \
	{ ( cd $(JAVA_CLIENT_DIR) && MAKE=$(MAKE) $(ANT) $(ANT_FLAGS) test-suite ) || OK=false; } && \
	$(MAKE) cleanup && $$OK

conformance16:
	$(test_verbose) OK=true && \
	$(MAKE) prepare && \
	{ $(MAKE) run-tests || OK=false; } && \
	{ ( cd $(JAVA_CLIENT_DIR) && MAKE=$(MAKE) $(ANT) $(ANT_FLAGS) test-suite ) || OK=false; } && \
	$(MAKE) cleanup && $$OK

qpid_testsuite:
	$(verbose) $(MAKE) update-qpid-testsuite

update-qpid-testsuite:
	$(verbose) svn co -r 906960 http://svn.apache.org/repos/asf/qpid/trunk/qpid/python qpid_testsuite
	# hg clone http://rabbit-hg.eng.vmware.com/mirrors/qpid_testsuite
	-$(verbose) patch -N -r - -p0 -d qpid_testsuite/ < qpid_patch

prepare-qpid-patch:
	$(verbose) cd qpid_testsuite && svn diff > ../qpid_patch && cd ..

run-qpid-testsuite: qpid_testsuite
	$(test_verbose) AMQP_SPEC=../rabbitmq-docs/specs/amqp0-8.xml qpid_testsuite/qpid-python-test -m tests_0-8 -I rabbit_failing.txt
	$(verbose) AMQP_SPEC=../rabbitmq-docs/specs/amqp0-9-1.xml qpid_testsuite/qpid-python-test -m tests_0-9 -I rabbit_failing.txt

clean:: clean-qpid-testsuite

clean-qpid-testsuite:
	$(gen_verbose) rm -rf qpid_testsuite

prepare: create_ssl_certs
	$(verbose) $(MAKE) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(HARE_BROKER_OPTIONS) \
		RABBITMQ_CONFIG_FILE=/does-not-exist \
		stop-node clean-node-db start-background-node
	$(verbose) $(MAKE) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(RABBIT_BROKER_OPTIONS) \
		RABBITMQ_CONFIG_FILE=/does-not-exist \
		stop-node clean-node-db start-background-node ${COVER_START} start-rabbit-on-node
	$(verbose) $(MAKE) RABBITMQ_NODENAME=hare start-rabbit-on-node

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
	$(exec_verbose) $(BROKER_DIR)/scripts/rabbitmqctl set_policy HA \
		".*" '{"ha-mode": "all"}'

disable-ha:
	$(exec_verbose) $(BROKER_DIR)/scripts/rabbitmqctl clear_policy HA

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
