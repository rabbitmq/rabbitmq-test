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
-include_lib("systest/include/systest.hrl").

-export([suite/0, all/0, groups/0]).
-export([init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2,
         init_per_testcase/2, end_per_testcase/2]).
-export([basic_enable/1, transitive_dependency_handling/1,
         offline_must_be_explicit/1, management_extension_handling/1]).

%% Configuration

suite() -> [{timetrap, systest:settings("time_traps.ha_cluster_SUITE")}].

all() ->
    [{group, with_running_nodes},
     {group, with_offline_nodes}].

groups() ->
    [{with_running_nodes, [shuffle],
      [basic_enable,
       transitive_dependency_handling]},
     {with_offline_nodes, [parallel],
      [{group, offline_changes},
       {group, management}]},
     {offline_changes, [shuffle],
      [offline_must_be_explicit]},
     {management, [sequence],
      [management_extension_handling]}].

%% Setup/Teardown

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, Config) ->
    {save_config, Config}.

init_per_testcase(_TC, Config) ->
    SUT = systest:active_sut(Config),
    [{N, Ref}] = systest:list_processes(SUT),
    file:delete(enabled_plugins_file(N)),
    [{node, N}, {node_ref, Ref}|Config].

end_per_testcase(_, _) ->
    ok.

%% Test Cases

basic_enable(Config) ->
    Node = ?config(node, Config),
    enable(rabbitmq_shovel, Node),
    verify_app_running(rabbitmq_shovel, Node),
    ok.

transitive_dependency_handling(Config) ->
    Node = ?config(node, Config),
    [begin
         enable(P, Node),
         verify_app_running(P, Node)
     end  || P <- [rabbitmq_shovel, rabbitmq_federation]],
    disable(rabbitmq_shovel, Node),
    verify_app_not_running(rabbitmq_shovel, Node),
    verify_app_running(amqp_client, Node),  %% federation requires amqp_client
    ok.

offline_must_be_explicit(Config) ->
    Node = ?config(node, Config),
    try
        enable(rabbitmq_shovel, Node),
        exit({node_offline, "without --offline, rabbitmq-plugins should crash"})
    catch _:{error_string, _} -> ok
    end.

management_extension_handling(Config) ->
    Node = ?config(node, Config),
    Ref  = ?config(node_ref, Config),
    enable_offline(rabbitmq_management, Node),
    enable_offline(rabbitmq_shovel_management, Node),

    systest:activate_process(Ref),
    verify_app_running(rabbitmq_shovel, Node),
    verify_app_running(rabbitmq_shovel_management, Node),
    disable(rabbitmq_shovel_management, Node),
    verify_app_not_running(rabbitmq_shovel_management, Node),
    ok.

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

enable(Plugin, Node) ->
    plugin_action(enable, Node, [atom_to_list(Plugin)]).

disable(Plugin, Node) ->
    plugin_action(disable, Node, [atom_to_list(Plugin)]).

enable_offline(Plugin, Node) ->
    plugin_action(enable, Node, [atom_to_list(Plugin)],
                  [{"--offline", true}]),
    {ok, Bin} = file:read_file(enabled_plugins_file(Node)),
    systest:log("enabled-plugins changed:~n~s~n", [Bin]),
    ok.

plugin_action(Command, Node, Args) ->
    plugin_action(Command, Node, Args, []).

plugin_action(Command, Node, Args, Opts) ->
    File = enabled_plugins_file(Node),
    {_, PDir} = systest:env("RABBITMQ_BROKER_DIR"),
    Dir = filename:join(PDir, "plugins"),
    rabbit_plugins_main:action(Command, Node, Args, Opts, File, Dir).

enabled_plugins_file(Node) ->
    {_, PkgDir} = systest:env("PACKAGE_DIR"),
    filename:join([PkgDir, "resources",
                   atom_to_list(Node) ++ "-enabled-plugins"]).

