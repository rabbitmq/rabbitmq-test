
{rabbit_node, [
    {startup, [
        {handler, systest_cli},
        {link_to_parent, true},
        {detached, false},
        {exit_on_eof, auto},
        {cover, true},
        {rpc_enabled, {true, {init, stop, []}}}
    ]},
    {flags, [
        {start, [
            {program, "%{RABBITMQ_BROKER_DIR}/scripts/rabbitmq-server"},
            {environment, [
                {"RABBITMQ_LOG_BASE", "${ct.priv_dir}/${ct.scope}"},
                {"RABBITMQ_CONFIG_FILE",
                        "${ct.priv_dir}/${ct.scope}/${proc.name}-conf.config"},
                {"RABBITMQ_PLUGINS_EXPAND_DIR",
                    "${ct.priv_dir}/${ct.scope}/rabbitmq-plugins-scratch"},
                {"RABBITMQ_ENABLED_PLUGINS_FILE",
                    "${ct.priv_dir}/${ct.scope}/enabled-plugins"},
                {"RABBITMQ_ALLOW_INPUT", "1"},
                {"RABBITMQ_NODENAME", "${proc.name}"},
                {"RABBITMQ_MNESIA_DIR",
                    "${ct.priv_dir}/${ct.scope}/rabbitmq-${proc.name}-mnesia"},
                {"RABBITMQ_PID_FILE",
                "${ct.priv_dir}/${ct.scope}/rabbitmq-${proc.name}-mnesia.pid"},
                {"RABBITMQ_NODE_PORT", "${proc.user.amqp_port}"},
                {"RABBITMQ_NODE_ONLY", "true"}
            ]}
        ]},
        {stop,  [
            {program, "%{RABBITMQ_BROKER_DIR}/scripts/rabbitmqctl"},
            {args, ["stop", "-n", "${proc.id}"]}
        ]}
    ]},
    {on_start, [{local, rabbit_ha_test_utils, start_rabbit, []}]},
    {on_stop,  [{local, rabbit_ha_test_utils, stop_rabbit, []}]}
]}.

{connected, [
    {on_join, [
        {local, rabbit_ha_test_utils, connect_to_node, []}
    ]},
    {on_stop, [
        {local, rabbit_ha_test_utils, disconnect_from_node, []}
    ]}
]}.

{start_cold, [
    {startup, [
        {activate_on_start, false}
    ]}
]}.

{two_nodes_unclustered, [
    {sut, [{localhost, [wibble, wobble]}]},
    {processes, [
        {wibble, [rabbit_node]},
        {wobble, [rabbit_node]},
        {jelly, [rabbit_node, start_cold]}
    ]},
    {user_data, [
        {wibble, [{amqp_port, 10672}]},
        {wobble, [{amqp_port, 10673}]}
    ]}
]}.

{plugin_handling_SUITE, [{all, two_nodes_unclustered}]}.

{three_node_cluster, [
    {sut, [{localhost, [a, b, c]}]},
    {processes, [
        {a, [rabbit_node, connected]},
        {b, [rabbit_node, connected]},
        {c, [rabbit_node, connected]}
    ]},
    {user_data, [
        {a, [{amqp_port, 10672}]},
        {b, [{amqp_port, 10673}]},
        {c, [{amqp_port, 10674}]}
    ]},
    {on_start, [
        %% NB: cluster on_start callbacks execute once *all* our nodes
        %% are up and running, so at this point we can cluster them...
        {local, rabbit_ha_test_utils, make_cluster, []},
        {local, rabbit_ha_test_utils, declare_ha_policies, []}
    ]}
]}.

{simple_ha_cluster_SUITE, [{all, three_node_cluster}]}.

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
        {n1, [{amqp_port, 11672}]},
        {n2, [{amqp_port, 11673}]},
        {n3, [{amqp_port, 11674}]},
        {n4, [{amqp_port, 11675}]},
        {n5, [{amqp_port, 11676}]},
        {n6, [{amqp_port, 11677}]}
    ]},
    {on_start, [
        %% NB: cluster on_start callbacks execute once *all* our nodes
        %% are up and running, so at this point we can cluster them...
        {local, rabbit_ha_test_utils, make_cluster, []},
        {local, rabbit_ha_test_utils, declare_ha_policies, []}
    ]}
]}.

{eager_synchronization_SUITE, [{all, three_node_cluster}]}.

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

{dynamic_ha_cluster_SUITE,
 [{all,                 three_node_cluster},
  {change_cluster_test, three_node_cluster_plus_two}]}.

{clustering_management_cluster, [
    {sut, [{localhost, [rabbit1, hare1, bunny1]}]},
    {processes, [
        {rabbit1, [rabbit_node, connected]},
        {hare1, [rabbit_node, connected]},
        {bunny1, [rabbit_node, connected]}
    ]},
    {user_data, [
        {rabbit1, [{amqp_port, 10672}]},
        {hare1, [{amqp_port, 10673}]},
        {bunny1, [{amqp_port, 10674}]}
    ]}
]}.

{clustering_management_SUITE, [{all, clustering_management_cluster}]}.

{slave_synchronization_SUITE, [{all, three_node_cluster}]}.
