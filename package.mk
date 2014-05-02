RELEASABLE:=false
DEPS:=rabbitmq-erlang-client
FILTER:=all
STANDALONE_TEST_COMMANDS:=multi_node_test_runner:run(\"$(FILTER)\")
