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
-module(partitions).

-compile(export_all).
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-import(rabbit_misc, [pget/2]).

ignore_with() -> cluster_abc. 
ignore(Cfgs) ->
    [A, B, C] = [pget(node, Cfg) || Cfg <- Cfgs],
    disconnect_reconnect([{B, C}]),
    timer:sleep(5000),
    [] = partitions(A),
    [C] = partitions(B),
    [B] = partitions(C),
    ok.

pause_on_down_with() -> cluster_abc. 
pause_on_down([_CfgA, CfgB, CfgC] = Cfgs) ->
    [A, B, C] = [pget(node, Cfg) || Cfg <- Cfgs],
    [set_mode(N, pause_minority) || N <- [A, B, C]],
    true = is_running(A),

    rabbit_test_utils:kill(CfgB, sigkill),
    timer:sleep(5000),
    true = is_running(A),

    rabbit_test_utils:kill(CfgC, sigkill),
    timer:sleep(5000),
    false = is_running(A),
    ok.

pause_on_disconnected_with() -> cluster_abc.
pause_on_disconnected(Cfgs) ->
    [A, B, C] = [pget(node, Cfg) || Cfg <- Cfgs],
    [set_mode(N, pause_minority) || N <- [A, B, C]],
    [(true = is_running(N)) || N <- [A, B, C]],
    disconnect([{A, B}, {A, C}]),
    timer:sleep(5000),
    [(true = is_running(N)) || N <- [B, C]],
    false = is_running(A),
    reconnect([{A, B}, {A, C}]),
    timer:sleep(5000),
    [(true = is_running(N)) || N <- [A, B, C]],
    Status = rpc:call(A, rabbit_mnesia, status, []),
    [] = pget(partitions, Status),
    ok.

autoheal_with() -> cluster_abc. 
autoheal(Cfgs) ->
    [A, B, C] = [pget(node, Cfg) || Cfg <- Cfgs],
    [set_mode(N, autoheal) || N <- [A, B, C]],
    Test = fun (Pairs) ->
                   disconnect_reconnect(Pairs),
                   await_startup([A, B, C]),
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

await_startup([]) ->
    ok;
await_startup([Node | Rest]) ->
    case rpc:call(Node, rabbit, is_running, []) of
        true -> await_startup(Rest);
        _    -> timer:sleep(100),
                await_startup([Node | Rest])
    end.

is_running(Node) -> rpc:call(Node, rabbit, is_running, []).
