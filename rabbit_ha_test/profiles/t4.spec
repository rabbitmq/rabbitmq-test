
%% write your own $USER.spec to override the default profile
%% or set SYSTEST_PROFILE in the environment to override both choices

{config, "{{ base_dir }}/resources/rabbit_nodes.config"}.
{config, "{{ base_dir }}/resources/simple_ha_cluster.config"}.
{config, "{{ base_dir }}/resources/multi_node_deaths.config"}.

{alias, test, "{{ base_dir }}/ebin"}.
{suites, test, simple_ha_cluster_SUITE}.
{cases, test, simple_ha_cluster_SUITE,
              [producer_confirms_survive_death_of_master]}.

{include, "/Users/t4/work/vmware/ct-uplift/rabbitmq-server/include"}.
{include, "/Users/t4/work/vmware/ct-uplift/rabbitmq-erlang-client/dist/rabbit_common-0.0.0/include"}.

{ct_hooks, [cth_log_redirect,
            {systest_cth, [], 0}]}.
{enable_builtin_hooks, true}.

