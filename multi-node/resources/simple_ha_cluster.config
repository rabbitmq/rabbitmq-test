
{three_node_cluster, [
    {sut, [{localhost, [a, b, c]}]},
    {processes, [
        {a, [rabbit_node, connected]},
        {b, [rabbit_node, connected]},
        {c, [rabbit_node, connected]}
    ]},
    {user_data, [
        {a, [{amqp_port, 5672}]},
        {b, [{amqp_port, 5673}]},
        {c, [{amqp_port, 5674}]}
    ]},
    {on_start, [
        %% NB: cluster on_start callbacks execute once *all* our nodes
        %% are up and running, so at this point we can cluster them...
        {local, rabbit_ha_test_utils, make_cluster, []}
    ]}
]}.

{simple_ha_cluster_SUITE, [{all, three_node_cluster}]}.

