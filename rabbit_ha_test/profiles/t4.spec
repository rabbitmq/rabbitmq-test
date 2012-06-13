
%% write your own $USER.spec to override the default profile
%% or set SYSTEST_PROFILE in the environment to override both choices

{config, "{{ base_dir }}/resources/rabbit_nodes.config"}.
{config, "{{ base_dir }}/resources/simple_ha_cluster.config"}.

{alias, test, "{{ base_dir }}/ebin"}.
{suites, test, simple_ha_cluster_SUITE}.
%% {cases, test, simple_ha_cluster_SUITE,
%              [starting_connected_nodes]}.

{include, "{{ base_dir }}/lib/rabbit/include"}.
{include, "{{ base_dir }}/lib/rabbit_common/include"}.
{include, "{{ base_dir }}/lib/amqp_client/include"}.

{ct_hooks, [cth_log_redirect,
            {systest_cth, [], 0}]}.
{enable_builtin_hooks, true}.

