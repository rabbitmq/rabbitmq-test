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
%% Copyright (c) 2007-2013 GoPivotal, Inc.  All rights reserved.
%%
-module(partition_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1,
         ignore/1, pause_on_down/1, pause_on_disconnected/1, autoheal/1]).

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
    disconnect_reconnect([{B, C}]),
    timer:sleep(5000),
    [] = partitions(A),
    [C] = partitions(B),
    [B] = partitions(C),
    ok.

pause_on_down(Config) ->
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

pause_on_disconnected(Config) ->
    SUT = systest:get_system_under_test(Config),
    [{A, _ARef},
     {B, _BRef},
     {C, _CRef}] = systest:list_processes(SUT),
    [set_mode(N, pause_minority) || N <- [A, B, C]],
    [(true = rabbit:is_running(N)) || N <- [A, B, C]],
    disconnect([{A, B}, {A, C}]),
    timer:sleep(5000),
    [(true = rabbit:is_running(N)) || N <- [B, C]],
    false = rabbit:is_running(A),
    reconnect([{A, B}, {A, C}]),
    timer:sleep(5000),
    [(true = rabbit:is_running(N)) || N <- [A, B, C]],
    Status = rpc:call(A, rabbit_mnesia, status, []),
    [] = proplists:get_value(partitions, Status),
    ok.

autoheal(Config) ->
    SUT = systest:active_sut(Config),
    [{A, _ARef},
     {B, _BRef},
     {C, _CRef}] = systest:list_processes(SUT),
    [set_mode(N, autoheal) || N <- [A, B, C]],
    Test = fun (Pairs) ->
                   disconnect_reconnect(Pairs),
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

%% We turn off auto_connect and wait a little while to make it more
%% like a real partition, and since Mnesia has problems with very
%% short partitions (and rabbit_node_monitor will in various ways attempt to
%% reconnect immediately).
disconnect_reconnect(Pairs) ->
    disconnect(Pairs),
    timer:sleep(1000),
    reconnect(Pairs).

disconnect(Pairs) ->
    dist_auto_connect(Pairs, never),
    [rpc:call(X, erlang, disconnect_node, [Y]) || {X, Y} <- Pairs].

reconnect(Pairs) ->
    dist_auto_connect(Pairs, always).

dist_auto_connect(Pairs, Val) ->
    {Xs, Ys} = lists:unzip(Pairs),
    Nodes = lists:usort(Xs ++ Ys),
    [rpc:call(Node, application, set_env, [kernel, dist_auto_connect, Val])
     || Node <- Nodes].

partitions(Node) ->
    rpc:call(Node, rabbit_node_monitor, partitions, []).
