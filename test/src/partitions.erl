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

-define(CONFIG, [start_abc, fun enable_dist_proxy/1]).
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

%% Make sure we do not confirm any messages after a partition has
%% happened but before we pause, since any such confirmations would be
%% lies.
pause_false_promises_with() -> [cluster_abc, ha_policy_all].
pause_false_promises([CfgA, CfgB | _] = Cfgs) ->
    [A, B, C] = [pget(node, Cfg) || Cfg <- Cfgs],
    set_mode(Cfgs, pause_minority),
    Ch = pget(channel, CfgA),
    amqp_channel:call(Ch, #'queue.declare'{queue = <<"test">>}),
    amqp_channel:call(Ch, #'confirm.select'{}),
    amqp_channel:register_confirm_handler(Ch, self()),

    %% Cause a partition after 1s
    Self = self(),
    spawn_link(fun () ->
                       timer:sleep(1000),
                       disconnect([{A, B}, {A, C}], 5000),
                       unlink(Self)
               end),

    %% Publish large no of messages, see how many we get confirmed
    [amqp_channel:cast(Ch, #'basic.publish'{routing_key = <<"test">>},
                       #amqp_msg{props = #'P_basic'{delivery_mode = 1}}) ||
        _ <- lists:seq(1, 1000000)],
    Confirmed = receive_acks(0),
    await_running(A, false),

    %% But how many made it onto the rest of the cluster?
    Ch2 = pget(channel, CfgB),
    #'queue.declare_ok'{message_count = Survived} = 
        amqp_channel:call(Ch2, #'queue.declare'{queue = <<"test">>}),
    ?debugVal({Confirmed, Survived}),
    ?assert(Confirmed =< Survived),
    ok.

receive_acks(Max) ->
    receive
        #'basic.ack'{delivery_tag = DTag} ->
            receive_acks(DTag)
    after 5000 ->
            Max
    end.

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

disconnect(Pairs)        -> disconnect(Pairs, 1000).
disconnect(Pairs, Delay) -> [block(X, Y, Delay) || {X, Y} <- Pairs].
reconnect(Pairs)         -> [allow(X, Y) || {X, Y} <- Pairs].

partitions(Node) ->
    rpc:call(Node, rabbit_node_monitor, partitions, []).

block(X, Y, Delay) ->
    rpc:call(X, inet_interceptable_dist, block, [Y, Delay]),
    rpc:call(Y, inet_interceptable_dist, block, [X, Delay]),
    rpc:call(X, erlang, disconnect_node, [Y]),
    rpc:call(Y, erlang, disconnect_node, [X]).

allow(X, Y) ->
    rpc:call(X, inet_interceptable_dist, allow, [Y]),
    rpc:call(Y, inet_interceptable_dist, allow, [X]).

await_running  (Node, Bool) -> await(Node, Bool, fun is_running/1).
await_listening(Node, Bool) -> await(Node, Bool, fun is_listening/1).

await(Node, Bool, Fun) ->
    case Fun(Node) of
        Bool -> ok;
        _    -> timer:sleep(100),
                await(Node, Bool, Fun)
    end.

is_running(Node) -> rpc:call(Node, rabbit, is_running, []).

is_listening(Node) ->
    case rpc:call(Node, rabbit_networking, node_listeners, [Node]) of
        []    -> false;
        [_|_] -> true;
        _     -> false
    end.

enable_dist_proxy(Cfgs) ->
    Nodes = [pget(node, Cfg) || Cfg <- Cfgs],
    [ok = rpc:call(Node, inet_interceptable_dist, enable, [Nodes])
     || Node <- Nodes],
    Cfgs.
