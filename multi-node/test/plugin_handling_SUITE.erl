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

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1]).
-export([basic_enable/1]).

%% NB: it can take almost a minute to start and cluster 3 nodes,
%% and then we need time left over to run the actual tests...
suite() -> [{timetrap, systest:settings("time_traps.ha_cluster_SUITE")}].

all() ->
    systest_suite:export_all(?MODULE).

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

basic_enable(Config) ->
    SUT = systest:active_sut(Config),
    [{A, _ARef},
     {_B, _BRef}] = systest:list_processes(SUT),
    enable(rabbitmq_shovel, A),
    AppInfo = rpc:call(A, rabbit_misc, which_applications, []),
    systest:log("Running Applications: ~p~n", [AppInfo]),
    {rabbitmq_shovel, _, _} = lists:keyfind(rabbitmq_shovel, 1, AppInfo),
    ok.

enable(Plugin, Node) ->
    plugin_action(enable, Node, [atom_to_list(Plugin)]).

%plugin_action(Command, Node) ->
%    plugin_action(Command, Node, [], []).

plugin_action(Command, Node, Args) ->
    plugin_action(Command, Node, Args, []).

plugin_action(Command, Node, Args, Opts) ->
    {ok, File} = rpc:call(Node, application, get_env,
                          [rabbit, enabled_plugins_file]),
    {_, PDir} = systest:env("RABBITMQ_BROKER_DIR"),
    Dir = filename:join(PDir, "plugins"),
    systest:log("PDir: ~p~nDir: ~p~nFile:~p~n", [PDir, Dir, File]),
    rabbit_plugins_main:action(Command, Node, Args, Opts, File, Dir).

