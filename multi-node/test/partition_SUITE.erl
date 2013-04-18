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
%% The Initial Developer of the Original Code is VMware, Inc.
%% Copyright (c) 2007-2013 VMware, Inc.  All rights reserved.
%%
-module(partition_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1,
         ignore/1, pause/1, autoheal/1]).

%% NB: it can take almost a minute to start and cluster 3 nodes,
%% and then we need time left over to run the actual tests...
suite() -> [{timetrap, systest:settings("time_traps.ha_cluster_SUITE")}].

all() ->
    systest_suite:export_all(?MODULE).

init_per_suite(Config) ->
    timer:start(),
    Config.

end_per_suite(_Config) ->
    ok.

ignore(Config) ->
    SUT = systest:active_sut(Config),
    [{A, _ARef},
     {B, _BRef},
     {C, _CRef}] = systest:list_processes(SUT),
    disconnect(B, C),
    timer:sleep(5000),
    [] = partitions(A),
    [C] = partitions(B),
    [B] = partitions(C),
    ok.

pause(Config) ->
    SUT = systest:active_sut(Config),
    [{A, _ARef},
     {B, BRef},
     {C, CRef}] = systest:list_processes(SUT),
    [set_mode(N, pause_minority) || N <- [A, B, C]],
    true = rabbit:is_running(A),

    systest:kill_and_wait(BRef),
    timer:sleep(5000),
    true = rabbit:is_running(A),

    systest:kill_and_wait(CRef),
    timer:sleep(5000),
    false = rabbit:is_running(A),
    ok.

autoheal(Config) ->
    SUT = systest:active_sut(Config),
    [{A, _ARef},
     {B, _BRef},
     {C, _CRef}] = systest:list_processes(SUT),
    [set_mode(N, autoheal) || N <- [A, B, C]],
    Test = fun (Pairs) ->
                   [disconnect(X, Y) || {X, Y} <- Pairs],
                   timer:sleep(5000),
                   [] = partitions(A),
                   [] = partitions(B),
                   [] = partitions(C)
           end,
    Test([{B, C}]),
    Test([{A, C}, {B, C}]),
    Test([{A, B}, {A, C}, {B, C}]),
    ok.

set_mode(Node, Mode) ->
    rpc:call(Node, application, set_env,
             [rabbit, cluster_partition_handling, Mode, infinity]).

disconnect(From, Node) ->
    rpc:call(From, erlang, disconnect_node, [Node]).

partitions(Node) ->
    {Node, Partitions} =
        rpc:call(Node, rabbit_node_monitor, partitions, []),
    Partitions.
