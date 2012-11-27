{dynamic_ha_cluster_SUITE,
 [{all,                 three_node_cluster},
  {change_cluster_test, three_node_cluster_plus_two}]}.

%% TODO How can we factor out the commonality?
{three_node_cluster_plus_two, [
    {sut, [{localhost, [a, b, c, d, e]}]},
    {processes, [
        {a, [rabbit_node, connected]},
        {b, [rabbit_node, connected]},
        {c, [rabbit_node, connected]},
        {d, [rabbit_node, start_cold]},
        {e, [rabbit_node, start_cold]}
    ]},
    {user_data, [
        {a, [{amqp_port, 10672}]},
        {b, [{amqp_port, 10673}]},
        {c, [{amqp_port, 10674}]},
        {d, [{amqp_port, 10675}]},
        {e, [{amqp_port, 10676}]}
    ]},
    {on_start, [
        %% NB: cluster on_start callbacks execute once *all* our nodes
        %% are up and running, so at this point we can cluster them...
        {local, rabbit_ha_test_utils, make_cluster, []}
    ]}
]}.
