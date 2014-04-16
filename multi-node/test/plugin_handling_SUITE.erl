%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2014 GoPivotal, Inc.  All rights reserved.
%%
-module(plugin_handling_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("systest/include/systest.hrl").
-include_lib("rabbit/include/rabbit.hrl").

-export([suite/0, all/0, groups/0]).
-export([init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2,
         init_per_testcase/2, end_per_testcase/2]).
-export([basic_enable/1, runtime_boot_step_handling/1,
         transitive_dependency_handling/1, manual_changes_then_disable/1,
         manual_changes_then_enable/1, offline_must_be_explicit/1,
         management_extension_handling/1,
         offline_changes_reflected_after_restart/1,
         running_broker_offline_changes/1]).

%% Configuration

suite() -> [{timetrap, systest:settings("time_traps.plugin_handling_SUITE")}].

all() -> [{group, all_tests}].

%% We have three nodes - defined in rabbit.resources by the two main
%% test sub-groups for all_tests and the sub-group management_plugins.
%% Note that we run some groups (and sub-groups) in parallel, which is
%% fine so long as no sharing (e.g., of the enabled-plugins file) occurs
%% between them. To ensure we've not overlooked any such inter-dependencies
%% between test cases, those that require isolation are run in a random
%% order (i.e., with 'shuffle').
%%
%% http://www.erlang.org/doc/apps/common_test/write_test_chapter.html#test_case_groups

groups() ->
    [{all_tests, [parallel],
      [{group, with_running_nodes},
       {group, with_offline_nodes}]},
     {with_running_nodes, [shuffle],
      [basic_enable,
       running_broker_offline_changes,
       runtime_boot_step_handling,
       transitive_dependency_handling,
       manual_changes_then_disable,
       manual_changes_then_enable]},
     {with_offline_nodes, [parallel],
      [{group, offline_changes},
       {group, management_plugins}]},
     {offline_changes, [shuffle],
      [offline_must_be_explicit,
       offline_changes_reflected_after_restart]},
     {management_plugins, [sequence],
      [management_extension_handling]}].

%% Setup/Teardown

init_per_suite(Config) ->
    inets:start(temporary),
    DataDir = proplists:get_value(data_dir, Config, "/tmp"),
    inets:start(httpc, [{data_dir, DataDir}]),
    [{current_scope, ?MODULE}|Config].

end_per_suite(Config) ->
    inets:stop(),
    Config.

init_per_group(Group, Config) ->
    case ?config(Group, Config) of
        Pid when is_pid(Pid) -> [{current_scope, Group}|Config];
        _                    -> Config
    end.

end_per_group(_, Config) ->
    Config.

init_per_testcase(_TC, Config) ->
    SUT = systest:get_system_under_test(Config),
    [{N, Ref}] = systest:list_processes(SUT),
    Config2 = [{node, N}, {node_ref, Ref}|Config],
    File = enabled_plugins_file(Config2),
    file:delete(File),
    filelib:ensure_dir(File),
    Config2.

end_per_testcase(_, Config) ->
    %% ensure that we cleanup after any tests that failed
    %% and left stuff active on a potentially running node.
    Node = ?config(node, Config),
    case net_adm:ping(Node) of
        pong -> plugin_action(disable, Node,
                              [atom_to_list(P) || P <- list_plugins()], Config);
        pang -> ok
    end,
    Config.

%% Online Test Cases

basic_enable(Config) ->
    Node = ?config(node, Config),
    enable(rabbitmq_shovel, Node, Config),
    verify_app_running(rabbitmq_shovel, Node),
    rabbit_ha_test_utils:stop_app(Node),
    rabbit_ha_test_utils:start_app(Node),
    verify_app_running(rabbitmq_shovel, Node),
    ok.

running_broker_offline_changes(Config) ->
    Node = ?config(node, Config),
    enable(rabbitmq_federation, Node, Config),
    verify_app_running(rabbitmq_federation, Node),

    disable_offline(rabbitmq_federation, Node, Config),
    verify_app_running(rabbitmq_federation, Node),

    disable(rabbitmq_federation, Node, Config),
    verify_app_not_running(rabbitmq_federation, Node),

    enable_offline(rabbitmq_federation, Node, Config),
    verify_app_not_running(rabbitmq_federation, Node),

    enable(rabbitmq_federation, Node, Config),
    verify_app_running(rabbitmq_federation, Node),
    ok.

runtime_boot_step_handling(Config) ->
    Node = ?config(node, Config),
    ExchangePlugin = rabbitmq_consistent_hash_exchange,

    enable(ExchangePlugin, Node, Config),
    Exchanges = rpc:call(Node, rabbit_registry, lookup_all, [exchange]),
    ?assertMatch({_, rabbit_exchange_type_consistent_hash},
                 lists:keyfind('x-consistent-hash', 1, Exchanges)),

    disable(ExchangePlugin, Node, Config),
    Exchanges2 = rpc:call(Node, rabbit_registry, lookup_all, [exchange]),
    ?assertMatch(false, lists:keymember('x-consistent-hash', 1, Exchanges2)),
    ok.

transitive_dependency_handling(Config) ->
    Node = ?config(node, Config),
    [begin
         enable(P, Node, Config),
         verify_app_running(P, Node)
     end  || P <- [rabbitmq_shovel, rabbitmq_federation]],
    disable(rabbitmq_shovel, Node, Config),
    verify_app_not_running(rabbitmq_shovel, Node),
    verify_app_running(amqp_client, Node),  %% federation requires amqp_client
    ok.

manual_changes_then_disable(Config) ->
    Node = ?config(node, Config),
    verify_app_not_running(rabbitmq_shovel, Node),
    enable_offline(rabbitmq_shovel, rabbit_nodes:make(foobar), Config),
    disable(rabbitmq_shovel, Node, Config),
    ok.

manual_changes_then_enable(Config) ->
    Node = ?config(node, Config),
    verify_app_not_running(rabbitmq_federation, Node),
    enable_offline(rabbitmq_federation, rabbit_nodes:make(foobar), Config),
    enable(rabbitmq_federation, Node, Config),
    verify_app_running(rabbitmq_federation, Node),
    ok.

%% Offline Test Cases

offline_must_be_explicit(Config) ->
    try
        enable(rabbitmq_shovel, rabbit_nodes:make(nonode), Config),
        exit({node_offline, "without --offline, rabbitmq-plugins should abort"})
    catch throw:{error_string, _} -> ok
    end.

offline_changes_reflected_after_restart(Config) ->
    Node = ?config(node, Config),
    Ref  = ?config(node_ref, Config),
    enable_offline(rabbitmq_mqtt, Node, Config),
    systest:activate_process(Ref),
    verify_app_running(rabbitmq_mqtt, Node),
    rabbit_ha_test_utils:stop_app(Node).

%% Special case (management extensions)

management_extension_handling(Config) ->
    Node = ?config(node, Config),
    Ref  = ?config(node_ref, Config),
    enable_offline(rabbitmq_management, Node, Config),
    systest:activate_process(Ref),  %% start the node
    verify_app_running(rabbitmq_management, Node),

    enable(rabbitmq_shovel_management, Node, Config),
    verify_app_running(rabbitmq_shovel_management, Node),

    disable(rabbitmq_shovel_management, Node, Config),
    verify_app_not_running(rabbitmq_shovel_management, Node),
    verify_app_running(rabbitmq_management, Node),

    %% port is configured in multi-node/resources/mgmt.config
    %% and the location passed via multi-node/resources/rabbit.resource
    {ok, {{_, Code, _}, _Headers, _Body}} =
        httpc:request("http://127.0.0.1:10001"),
    ?assertEqual(Code, 200),
    ok.

%% Utilities

list_plugins() ->
    {_, Dir} = systest:env("RABBITMQ_BROKER_DIR"),
    PluginsDir = filename:join(Dir, "plugins"),
    [Plugin#plugin.name || Plugin <- rabbit_plugins:list(PluginsDir)].

verify_app_running(App, Node) ->
    Running = get_running_apps(Node),
    case lists:keyfind(App, 1, Running) of
        {App, _, _} -> ok;
        false       -> ct:fail("~p not running: ~p~n", [App, Running])
    end.

verify_app_not_running(App, Node) ->
    false = lists:keyfind(App, 1, get_running_apps(Node)).

get_running_apps(Node) ->
    rpc:call(Node, rabbit_misc, which_applications, []).

enable(Plugin, Node, Config) ->
    plugin_action(enable, Node, [atom_to_list(Plugin)], Config).

disable(Plugin, Node, Config) ->
    plugin_action(disable, Node, [atom_to_list(Plugin)], Config).

enable_offline(Plugin, Node, Config) ->
    plugin_action(enable, Node, [atom_to_list(Plugin)],
                  [{"--offline", true}], Config),
    File = enabled_plugins_file(Config),
    {ok, Bin} = file:read_file(File),
    systest:log("~s changed: ~s~n", [File, Bin]),
    ok.

disable_offline(Plugin, Node, Config) ->
    plugin_action(enable, Node, [atom_to_list(Plugin)],
                  [{"--offline", true}], Config).

plugin_action(Command, Node, Args, Config) ->
    plugin_action(Command, Node, Args, [], Config).

plugin_action(Command, Node, Args, Opts, Config) ->
    File = enabled_plugins_file(Config),
    {_, PDir} = systest:env("RABBITMQ_BROKER_DIR"),
    Dir = filename:join(PDir, "plugins"),
    rabbit_plugins_main:action(Command, Node, Args, Opts, File, Dir).

enabled_plugins_file(Config) ->
    {_, Dir} = systest:env("PACKAGE_DIR"),
    Scope = ?config(current_scope, Config),
    filename:join([Dir, "test", "data", Scope, "enabled-plugins"]).

