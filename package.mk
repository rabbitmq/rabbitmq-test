DEPS:=rabbitmq-erlang-client
FILTER:=all
COVER:=false
STANDALONE_TEST_COMMANDS:=rabbit_test_runner:run_multi(\"$(UMBRELLA_BASE_DIR)/rabbitmq-server\",\"$(PACKAGE_DIR)/test/ebin\",\"$(FILTER)\",$(COVER),none)
