
{rabbit_node, [
    {startup, [
        {handler, systest_cli},
        {link_to_parent, true},
        {detached, false},
        {cover, true},
        {rpc_enabled, {true, {init, stop, []}}}
    ]},
    {flags, [
        {start, [
            {program, "%{RABBITMQ_BROKER_DIR}/scripts/rabbitmq-server"},
            {environment, [
                {"RABBITMQ_LOG_BASE", "${ct.priv_dir}/${ct.scope}"},
                {"RABBITMQ_PLUGINS_EXPAND_DIR",
                    "${ct.priv_dir}/${ct.scope}/${proc.name}-plugins-scratch"},
                {"RABBITMQ_ENABLED_PLUGINS_FILE",
                    "${ct.priv_dir}/${ct.scope}/${proc.name}-enabled-plugins"},
                {"RABBITMQ_NODE_IP_ADDRESS", "0.0.0.0"},
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
    {on_start, [
        {local, rabbit_ha_test_utils, start_rabbit, []}
    ]}
]}.

{connected, [
    {on_join, [
        {local, rabbit_ha_test_utils, connect_to_node, []}
    ]},
    {on_stop, [
        {local, rabbit_ha_test_utils, disconnect_from_node, []}
    ]}
]}.

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

