DEPS:=rabbitmq-erlang-client
FILTER:=all
COVER:=false
STANDALONE_TEST_COMMANDS:=rabbit_test_runner:run_multi(\"test/ebin\",\"$(FILTER)\",$(COVER),none)
