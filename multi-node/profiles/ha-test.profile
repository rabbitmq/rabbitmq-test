
{targets,  [simple_ha_cluster_SUITE,
            dynamic_ha_cluster_SUITE,
            eager_synchronization_SUITE,
            clustering_management_SUITE,
            slave_synchronization_SUITE]}.
{hooks,     [{cth_surefire, [{path, "../ha-test.xml"}], 100},
             {cth_log_redirect, [], 100},
             {systest_cth, [], 1000}]}.
{aggressive_teardown, {minutes, 5}}.
{setup_timetrap,      {minutes, 5}}.
{teardown_timetrap,   {minutes, 3}}.
{execution_timetrap,  {hours, 1}}.
{log_dir, "./logs"}.
{output_dir, "./logs"}.
