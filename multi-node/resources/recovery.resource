
{event_log_failure_during_shutdown, [
    {sut, [{localhost, [a]}]},
    {processes, [
        {a, [rabbit_node]}
    ]},
    {user_data, [
        {a, [{amqp_port, 5672}]}
    ]}
]}.

{ha_recovery_SUITE, [{all, three_node_cluster}]}.

