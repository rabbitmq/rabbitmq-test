
{killing_multiple_intermediate_nodes, [
    {sut, [{localhost, [n1, n2, n3, n4, n5, n6]}]},
    {processes, [
        {n1, [rabbit_node, connected]},
        {n2, [rabbit_node, connected]},
        {n3, [rabbit_node, connected]},
        {n4, [rabbit_node, connected]},
        {n5, [rabbit_node, connected]},
        {n6, [rabbit_node, connected]}
    ]},
    {user_data, [
        {n1, [{amqp_port, 10672}]},
        {n2, [{amqp_port, 10673}]},
        {n3, [{amqp_port, 10674}]},
        {n4, [{amqp_port, 10675}]},
        {n5, [{amqp_port, 10676}]},
        {n6, [{amqp_port, 10677}]}
    ]},
    {on_start, [
        %% NB: cluster on_start callbacks execute once *all* our nodes
        %% are up and running, so at this point we can cluster them...
        {local, rabbit_ha_test_utils, make_cluster, []}
    ]}
]}.
