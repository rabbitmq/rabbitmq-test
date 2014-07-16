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

-define(CONFIG, [cluster_abc]).
%% We set ticktime to 1s and the pretend failed TCP connection time to 1s so to
%% make absolutely sure it passes...
-define(DELAY, 5000).

ignore_with() -> ?CONFIG.
ignore(Cfgs) ->
    [A, B, C] = [pget(node, Cfg) || Cfg <- Cfgs],
    disconnect_reconnect([{B, C}]),
    timer:sleep(?DELAY),
    [] = partitions(A),
    [C] = partitions(B),
    [B] = partitions(C),
    ok.

pause_on_down_with() -> ?CONFIG.
pause_on_down([CfgA, CfgB, CfgC] = Cfgs) ->
    A = pget(node, CfgA),
    set_mode(Cfgs, pause_minority),
    true = is_running(A),

    rabbit_test_util:kill(CfgB, sigkill),
    timer:sleep(?DELAY),
    true = is_running(A),

    rabbit_test_util:kill(CfgC, sigkill),
    await_running(A, false),
    ok.

pause_on_disconnected_with() -> ?CONFIG.
pause_on_disconnected(Cfgs) ->
    [A, B, C] = [pget(node, Cfg) || Cfg <- Cfgs],
    set_mode(Cfgs, pause_minority),
    [(true = is_running(N)) || N <- [A, B, C]],
    disconnect([{A, B}, {A, C}]),
    await_running(A, false),
    [await_running(N, true) || N <- [B, C]],
    reconnect([{A, B}, {A, C}]),
    [await_running(N, true) || N <- [A, B, C]],
    Status = rpc:call(B, rabbit_mnesia, status, []),
    [] = pget(partitions, Status),
    ok.

autoheal_with() -> ?CONFIG.
autoheal(Cfgs) ->
    [A, B, C] = [pget(node, Cfg) || Cfg <- Cfgs],
    set_mode(Cfgs, autoheal),
    Test = fun (Pairs) ->
                   disconnect_reconnect(Pairs),
                   [await_running(N, true) || N <- [A, B, C]],
                   [] = partitions(A),
                   [] = partitions(B),
                   [] = partitions(C)
           end,
    Test([{B, C}]),
    Test([{A, C}, {B, C}]),
    Test([{A, B}, {A, C}, {B, C}]),
    ok.

set_mode(Cfgs, Mode) ->
    [set_env(Cfg, rabbit, cluster_partition_handling, Mode) || Cfg <- Cfgs].

set_env(Cfg, App, K, V) ->
    rpc:call(pget(node, Cfg), application, set_env, [App, K, V]).

disconnect_reconnect(Pairs) ->
    disconnect(Pairs),
    timer:sleep(?DELAY),
    reconnect(Pairs).

disconnect(Pairs) -> [block(X, Y) || {X, Y} <- Pairs].
reconnect(Pairs)  -> [allow(X, Y) || {X, Y} <- Pairs].

partitions(Node) ->
    rpc:call(Node, rabbit_node_monitor, partitions, []).

block(X, Y) ->
    block(X, Y, 1000).

block(X, Y, Delay) ->
    rpc:call(X, inet_interceptable_dist, block, [Y, Delay]),
    rpc:call(Y, inet_interceptable_dist, block, [X, Delay]),
    rpc:call(X, erlang, disconnect_node, [Y]),
    rpc:call(Y, erlang, disconnect_node, [X]).

allow(X, Y) ->
    rpc:call(X, inet_interceptable_dist, allow, [Y]),
    rpc:call(Y, inet_interceptable_dist, allow, [X]).

await_running(Node, Bool) ->
    case is_running(Node) of
        Bool -> ok;
        _    -> timer:sleep(100),
                await_running(Node, Bool)
    end.

is_running(Node) -> rpc:call(Node, rabbit, is_running, []).
