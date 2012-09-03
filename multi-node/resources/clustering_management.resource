{clustering_management_cluster, [
    {sut, [{localhost, [rabbit, hare, bunny]}]},
    {processes, [
        {rabbit, [rabbit_node, connected]},
        {hare, [rabbit_node, connected]},
        {bunny, [rabbit_node, connected]}
    ]},
    {user_data, [
        {rabbit, [{amqp_port, 5672}]},
        {hare, [{amqp_port, 5673}]},
        {bunny, [{amqp_port, 5674}]}
    ]}
]}.

{clustering_management_SUITE, [{all, clustering_management_cluster}]}.
