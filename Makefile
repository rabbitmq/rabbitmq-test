.PHONY: all lite conformance16 update-qpid-testsuite run-qpid-testsuite \
	prepare restart-app restart-secondary-node cleanup force-snapshot

BROKER_DIR=../rabbitmq-server
TEST_DIR=../rabbitmq-java-client

TEST_RABBIT_PORT=5672
TEST_HARE_PORT=5673

COVER=true

ifeq ($(COVER), true)
COVER_START=start-cover
COVER_STOP=stop-cover
else
COVER_START=
COVER_STOP=
endif

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
	svn co http://svn.apache.org/repos/asf/qpid/trunk/qpid/python -r r732436 qpid_testsuite

run-qpid-testsuite: qpid_testsuite
	cd qpid_testsuite;./run-tests -v -s ../../rabbitmq-docs/specs/amqp0-8.xml -I ../rabbit_failing.txt;cd ..

clean:
	rm -rf qpid_testsuite

prepare:
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		cleandb start-background-node start-rabbit-on-node
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		cleandb start-background-node ${COVER_START} start-rabbit-on-node 

restart-app:
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		stop-rabbit-on-node start-rabbit-on-node

restart-secondary-node:
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		stop-node start-background-node start-rabbit-on-node

force-snapshot:
	$(MAKE) -C $(BROKER_DIR) force-snapshot

cleanup:
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODENAME=hare \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_HARE_PORT} \
		stop-rabbit-on-node stop-node
	$(MAKE) -C $(BROKER_DIR) \
		RABBITMQ_NODE_IP_ADDRESS=0.0.0.0 \
		RABBITMQ_NODE_PORT=${TEST_RABBIT_PORT} \
		stop-rabbit-on-node ${COVER_STOP} stop-node
