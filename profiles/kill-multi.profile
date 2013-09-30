
{resource,  ["resources/rabbit.resource"]}.
{targets,  [multi_node_deaths_SUITE]}.
{aggressive_teardown, {minutes, 12}}.
{setup_timetrap,      {minutes, 5}}.     
{teardown_timetrap,   {minutes, 10}}.
{execution_timetrap,  {hours, 1}}.
{log_dir, "./logs"}.
{output_dir, "./logs"}.
{hooks,     [{cth_surefire, [{path, "../kill-multi.xml"}], 100},
             {cth_log_redirect, [], 100},
             {systest_cth, [], 1000}]}.

