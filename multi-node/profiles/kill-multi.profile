
{resource,  ["resources/rabbit_nodes.resource",
             "resources/multi_node_deaths.resource"]}.
{targets,  [multi_node_deaths_SUITE]}.
{aggressive_teardown, {minutes, 15}}.
{setup_timetrap,      {minutes, 5}}.     
{teardown_timetrap,   {minutes, 10}}.

