
{targets,  [multi_node_deaths_SUITE,
            simple_ha_cluster_SUITE,
            dynamic_ha_cluster_SUITE,
            eager_synchronization_SUITE,
            clustering_management_SUITE,
            slave_synchronization_SUITE]}.
{aggressive_teardown, {minutes, 15}}.
{setup_timetrap,      {minutes, 5}}.
{teardown_timetrap,   {minutes, 10}}.
{execution_timetrap,  {hours, 1}}.
{log_dir, "./logs"}.
{output_dir, "./logs"}.

