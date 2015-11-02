# RabbitMQ Test Suites

## Useful targets

    make unit  # runs the Erlang unit tests
    make lite  # runs the Erlang unit tests and the Java client / functional tests
    make full  # runs both the above plus the QPid test suite
    make tests # runs the Erlang multi-node integration tests + all of the above

The multi-node tests take a long time, so you might want to run a subset:

    make tests FILTER=dynamic_ha               # <- run just one suite
    make tests FILTER=dynamic_ha:change_policy # <- run just one test

The multi-node tests also default to coverage on, to turn it off:

    make tests COVER=false

This repository is not related to plugin tests; run "make tests" in a
plugin directory to test that plugin.
