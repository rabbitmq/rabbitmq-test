DEPS:=rabbitmq-erlang-client
FILTER:=all
COVER:=false
STANDALONE_TEST_COMMANDS:=multi_node_test_runner:run(\"test/ebin\",\"$(FILTER)\",$(COVER))
