.PHONY: all lite conformance16 update-qpid-testsuite run-qpid-testsuite \
	prepare restart-app restart-secondary-node cleanup force-snapshot

BROKER_DIR=../rabbitmq-server
TEST_DIR=../rabbitmq-java-client

TEST_RABBIT_PORT=5672
TEST_HARE_PORT=5673
TEST_RABBIT_SSL_PORT=5671
TEST_HARE_SSL_PORT=5670

COVER=true

ifeq ($(COVER), true)
COVER_START=start-cover
COVER_STOP=stop-cover
else
COVER_START=
COVER_STOP=
endif

# we actually want to test for ssl above 3.9 (eg >= 3.10), but this
# comparison is buggy because it doesn't believe 10 > 9, so it doesn't
# believe 3.10 > 3.9. As a result, we cheat, and use the erts version
# instead. SSL 3.10 came out with R13B, which included erts 5.7.1, so
# we require > 5.7.0.
SSL_VERIFY=$(shell if [ $$(erl -noshell -eval 'io:format(erlang:system_info(version)), halt().') \> "5.7.0" ]; then echo "true"; else echo "false"; fi)
ifeq (true,$(SSL_VERIFY))
SSL_VERIFY_OPTION :={verify,verify_peer},{fail_if_no_peer_cert,false}
else
SSL_VERIFY_OPTION :={verify_code,1}
endif
export SSL_CERTS_DIR := $(realpath certs)
export PASSWORD := test
RABBIT_SSL_BROKER_OPTIONS := "-rabbit ssl_listeners [{\\\"0.0.0.0\\\",$(TEST_RABBIT_SSL_PORT)}] -rabbit ssl_options [{cacertfile,\\\"$(SSL_CERTS_DIR)/testca/cacert.pem\\\"},{certfile,\\\"$(SSL_CERTS_DIR)/server/cert.pem\\\"},{keyfile,\\\"$(SSL_CERTS_DIR)/server/key.pem\\\"},$(SSL_VERIFY_OPTION)]"
HARE_SSL_BROKER_OPTIONS := "-rabbit ssl_listeners [{\\\"0.0.0.0\\\",$(TEST_HARE_SSL_PORT)}] -rabbit ssl_options [{cacertfile,\\\"$(SSL_CERTS_DIR)/testca/cacert.pem\\\"},{certfile,\\\"$(SSL_CERTS_DIR)/server/cert.pem\\\"},{keyfile,\\\"$(SSL_CERTS_DIR)/server/key.pem\\\"},$(SSL_VERIFY_OPTION)]"

all:
	OK=true && \
	$(MAKE) prepare && \
	{ $(MAKE) -C $(BROKER_DIR) run-tests || OK=false; } && \
	{ $(MAKE) run-qpid-testsuite || OK=false; } && \
	{ ( cd $(TEST_DIR) && ant test-suite ) || OK=false; } && \
	$(MAKE) cleanup && $$OK

lite:
	OK=true && \
	$(MAKE) prepare && \
	{ $(MAKE) -C $(BROKER_DIR) run-tests || OK=false; } && \
	{ ( cd $(TEST_DIR) && ant test-suite ) || OK=false; } && \
	$(MAKE) cleanup && $$OK

conformance16:
	OK=true && \
	$(MAKE) prepare && \
	{ $(MAKE) -C $(BROKER_DIR) run-tests || OK=false; } && \
	{ ( cd $(TEST_DIR) && ant test-suite ) || OK=false; } && \
	$(MAKE) cleanup && $$OK

qpid_testsuite:
	$(MAKE) update-qpid-testsuite

update-qpid-testsuite:
	svn co -r 906960 http://svn.apache.org/repos/asf/qpid/trunk/qpid/python qpid_testsuite

run-qpid-testsuite: qpid_testsuite
	cp qpid_config.py qpid_testsuite/
	cd qpid_testsuite; AMQP_SPEC=../../rabbitmq-docs/specs/amqp0-9-1.xml ./qpid-python-test -m tests -m tests_0-9 -I ../rabbit_failing.txt;cd ..

clean:
	rm -rf qpid_testsuite

prepare: create_ssl_certs
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(HARE_SSL_BROKER_OPTIONS) \
		stop-node cleandb start-background-node start-rabbit-on-node
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(RABBIT_SSL_BROKER_OPTIONS) \
		stop-node cleandb start-background-node ${COVER_START} start-rabbit-on-node

restart-app:
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(RABBIT_SSL_BROKER_OPTIONS) \
		stop-rabbit-on-node start-rabbit-on-node

restart-node:
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(RABBIT_SSL_BROKER_OPTIONS) \
		stop-node start-background-node start-rabbit-on-node	

restart-secondary-node:
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(HARE_SSL_BROKER_OPTIONS) \
		stop-node start-background-node start-rabbit-on-node

force-snapshot:
	$(MAKE) -C $(BROKER_DIR) force-snapshot

cleanup:
	-$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(HARE_SSL_BROKER_OPTIONS) \
		stop-rabbit-on-node stop-node
	-$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		RABBITMQ_SERVER_START_ARGS=$(RABBIT_SSL_BROKER_OPTIONS) \
		stop-rabbit-on-node ${COVER_STOP} stop-node

create_ssl_certs:
	$(MAKE) -C certs DIR=$(SSL_CERTS_DIR) clean all
