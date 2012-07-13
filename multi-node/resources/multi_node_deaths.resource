
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
        {n1, [{amqp_port, 5672}]},
        {n2, [{amqp_port, 5673}]},
        {n3, [{amqp_port, 5674}]},
        {n4, [{amqp_port, 5675}]},
        {n5, [{amqp_port, 5676}]},
        {n6, [{amqp_port, 5677}]}
    ]}
]}.
