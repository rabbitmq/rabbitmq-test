
{targets,  [simple_ha_cluster_SUITE,
            dynamic_ha_cluster_SUITE,
            eager_synchronization_SUITE,
            clustering_management_SUITE,
            slave_synchronization_SUITE]}.
{aggressive_teardown, {minutes, 5}}.
{setup_timetrap,      {minutes, 5}}.
{teardown_timetrap,   {seconds, 100}}.
{execution_timetrap,  {hours, 1}}.

