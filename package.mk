RELEASABLE:=false
DEPS:=rabbitmq-erlang-client systest-wrapper
STANDALONE_TEST_COMMANDS:=rabbit_systest:profile_test(\"ha-test\",rabbit_systest:cover_dirs(\"./build/dep-apps\")) rabbit_systest:profile_test(\"kill-multi\",[{no_cover,true}])
ERL_OPTS:=-pa $(PACKAGE_DIR)/test/ebin -pa $(PACKAGE_DIR)/build/dep-apps/*/ebin -pa $(abspath $(PACKAGE_DIR)/../rabbitmq-server/ebin)
