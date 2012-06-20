
{config, "{{ base_dir }}/resources/rabbit_nodes.config"}.
{config, "{{ base_dir }}/resources/simple_ha_cluster.config"}.

{alias, test, "{{ base_dir }}/ebin"}.
{suites, test, simple_ha_cluster_SUITE}.

{include, "{{ base_dir }}/lib/rabbit/include"}.
{include, "{{ base_dir }}/lib/rabbit_common/include"}.
{include, "{{ base_dir }}/lib/amqp_client/include"}.

{ct_hooks, [cth_log_redirect,
        {systest_cth, [], 0}]}.
{enable_builtin_hooks, true}.
