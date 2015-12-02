# RabbitMQ Test Suites

## Useful targets

    make unit  # runs the Erlang unit tests
    make lite  # runs the Erlang unit tests and the Java client / functional tests
    make full  # runs both the above plus the QPid test suite
    make tests # runs the Erlang multi-node integration tests + all of the above

The multi-node tests take a long time, so you might want to run a subset:

    make standalone-tests FILTER=dynamic_ha               # <- run just one suite
    make standalone-tests FILTER=dynamic_ha:change_policy # <- run just one test

The multi-node tests also default to coverage on, to turn it off:

    make standalone-tests COVER=false

`tests-with-broker` target also supports `FILTER` and `COVER`
arguments, but instead runs modern single-node test - where all suites
are executed inside single broker instance.

This repository is not related to plugin tests; run "make tests" in a
plugin directory to test that plugin.

## Kinds of tests

There are different kinds of tests located inside `tests/src` directory:
- Legacy test suite that can be only run as a whole using
  `rabbit_tests:all_tests/0`. Tests are run inside a running broker,
  so they could perform testing by doing direct calls to modules under
  the test.
- Modern tests that are run in a running broker. This tests are
  auto-discovered by function name, which should end with `_test`. As
  tests are being run inside a running broker, testing can be
  performed by directly calling modules under the test. But as tests
  are run independently by eunit, some care should be taken to
  preserve broker in a good state. (It's not a big problem for legacy
  test set as they stop after detecting the first failure).
- Multi-node tests, where node(s) are being setup from clean slate for
  every test case. This test are auto-disovered by function name,
  which should end with `_with`. Those `_with` functions provide
  meta-information about the way that nodes(s) should be setup, actual
  testing code should be placed in the function without `_with`
  postfix.

## Writing multi-node tests

Multi-node test-case is represented by 2 functions: test itself with
arbitary name, and setup metadata in a function named like the test
function plus suffix `_with`. So, e.g. test named `abc` should be
represented by: `abc/1` and `abc_with/0`.

`rabbit_test_runner` calls `XXX_with/0` and performs all
initializations mentioned there, accumulating some config data while
doing this. Possible return values for `_with` functions are of type
`rabbit_test_runner:initializers()`:
- atom referencing predefined function from `rabbit_test_configs`.
- function reference which should accept single parameter of type
  `rabbit_test_configs:config()`.
- list of things mentioned above.

In the end we will have a proplist (or list of proplists for each
node), that will be passed to test case itself.
