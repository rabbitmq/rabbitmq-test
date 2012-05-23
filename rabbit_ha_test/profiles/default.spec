
{logdir, "{{ base_dir }}/logs"}.

{config, "{{ base_dir }}/resources/simple_ha_cluster.config"}.
{config, "{{ base_dir }}/resources/large_ha_cluster.config"}.
{config, "{{ base_dir }}/resources/distributed_ha_cluster.config"}.

{alias, test, "{{ base_dir }}/test"}.
{suites, test, all}.

{include, "{{ base_dir }}/lib/rabbit/include"}.
{include, "{{ base_dir }}/lib/rabbit_common/include"}.
{include, "{{ base_dir }}/lib/amqp_client/include"}.
