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
-module(eager_synchronization_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-define(QNAME, <<"ha.two.test">>).
-define(QNAME_AUTO, <<"ha.auto.test">>).
-define(MESSAGE_COUNT, 2000).

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1,
         eager_sync_test/1, eager_sync_cancel_test/1, eager_sync_auto_test/1,
         eager_sync_auto_on_policy_change_test/1, eager_sync_requeue_test/1]).

-import(rabbit_ha_test_utils, [set_policy/5, a2b/1]).

%% NB: it can take almost a minute to start and cluster 3 nodes,
%% and then we need time left over to run the actual tests...
suite() -> [{timetrap, systest:settings("time_traps.eager_sync")}].

all() ->
    systest_suite:export_all(?MODULE).

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

eager_sync_test(Config) ->
    %% Queue is on AB but not C.
    {_Cluster, [{{A, _ARef}, {_AConn, ACh}},
                {{B, _BRef}, {_BConn, _BCh}},
                {{C, _CRef}, {_CConn, Ch}}]} =
        rabbit_ha_test_utils:cluster_members(Config),

    amqp_channel:call(ACh, #'queue.declare'{queue   = ?QNAME,
                                            durable = true}),
    amqp_channel:call(Ch, #'confirm.select'{}),

    %% Don't sync, lose messages
    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    restart(A),
    restart(B),
    consume(Ch, ?QNAME, 0),

    %% Sync, keep messages
    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    restart(A),
    ok = sync(C, ?QNAME),
    restart(B),
    consume(Ch, ?QNAME, ?MESSAGE_COUNT),

    %% Check the no-need-to-sync path
    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    ok = sync(C, ?QNAME),
    consume(Ch, ?QNAME, ?MESSAGE_COUNT),

    %% keep unacknowledged messages
    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    fetch(Ch, ?QNAME, 2),
    restart(A),
    fetch(Ch, ?QNAME, 3),
    sync(C, ?QNAME),
    restart(B),
    consume(Ch, ?QNAME, ?MESSAGE_COUNT),

    ok.

eager_sync_cancel_test(Config) ->
    %% Queue is on AB but not C.
    {_Cluster, [{{A, _ARef}, {_AConn, ACh}},
                {{B, _BRef}, {_BConn, _BCh}},
                {{C, _CRef}, {_Conn, Ch}}]} =
        rabbit_ha_test_utils:cluster_members(Config),

    amqp_channel:call(ACh, #'queue.declare'{queue   = ?QNAME,
                                            durable = true}),
    amqp_channel:call(Ch, #'confirm.select'{}),
    {ok, not_syncing} = sync_cancel(C, ?QNAME), %% Idempotence
    eager_sync_cancel_test2(A, B, C, Ch).

eager_sync_cancel_test2(A, B, C, Ch) ->
    %% Sync then cancel
    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    restart(A),
    spawn_link(fun() -> ok = sync_nowait(C, ?QNAME) end),
    case wait_for_syncing(C, ?QNAME, 1) of
        ok ->
            case sync_cancel(C, ?QNAME) of
                ok ->
                    wait_for_running(C, ?QNAME),
                    restart(B),
                    consume(Ch, ?QNAME, 0),

                    {ok, not_syncing} = sync_cancel(C, ?QNAME), %% Idempotence
                    ok;
                {ok, not_syncing} ->
                    %% Damn. Syncing finished between wait_for_syncing/3 and
                    %% sync_cancel/2 above. Start again.
                    amqp_channel:call(Ch, #'queue.purge'{queue = ?QNAME}),
                    eager_sync_cancel_test2(A, B, C, Ch)
            end;
        synced_already ->
            %% Damn. Syncing finished before wait_for_syncing/3. Start again.
            amqp_channel:call(Ch, #'queue.purge'{queue = ?QNAME}),
            eager_sync_cancel_test2(A, B, C, Ch)
    end.

eager_sync_auto_test(Config) ->
    %% Queue is on AB but not C.
    {_Cluster, [{{A, _ARef}, {_AConn, ACh}},
                {{B, _BRef}, {_BConn, _BCh}},
                {{C, _CRef}, {_CConn, Ch}}]} =
        rabbit_ha_test_utils:cluster_members(Config),

    amqp_channel:call(ACh, #'queue.declare'{queue   = ?QNAME_AUTO,
                                            durable = true}),
    amqp_channel:call(Ch, #'confirm.select'{}),

    %% Sync automatically, don't lose messages
    publish(Ch, ?QNAME_AUTO, ?MESSAGE_COUNT),
    restart(A),
    wait_for_sync(C, ?QNAME_AUTO),
    restart(B),
    wait_for_sync(C, ?QNAME_AUTO),
    consume(Ch, ?QNAME_AUTO, ?MESSAGE_COUNT),

    ok.

eager_sync_auto_on_policy_change_test(Config) ->
    %% Queue is on AB but not C.
    {_Cluster, [{{A, _ARef}, {_AConn, ACh}},
                {{B, _BRef}, {_BConn, _BCh}},
                {{C, _CRef}, {_CConn, Ch}}]} =
        rabbit_ha_test_utils:cluster_members(Config),

    amqp_channel:call(ACh, #'queue.declare'{queue   = ?QNAME,
                                            durable = true}),
    amqp_channel:call(Ch, #'confirm.select'{}),

    %% Sync automatically once the policy is changed to tell us to.
    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    restart(A),
    set_policy(A, <<"^ha.two.">>, <<"nodes">>, [a2b(A), a2b(B)],
               <<"automatic">>),
    wait_for_sync(C, ?QNAME),

    ok.

eager_sync_requeue_test(Config) ->
    %% Queue is on AB but not C.
    {_Cluster, [{{_A, _ARef}, {_AConn, ACh}},
                {{B,  _BRef}, {_BConn, _BCh}},
                {{C,  _CRef}, {_CConn, Ch}}]} =
        rabbit_ha_test_utils:cluster_members(Config),

    amqp_channel:call(ACh, #'queue.declare'{queue   = ?QNAME,
                                            durable = true}),
    amqp_channel:call(Ch, #'confirm.select'{}),

    publish(Ch, ?QNAME, 2),
    {#'basic.get_ok'{delivery_tag = TagA}, _} =
        amqp_channel:call(Ch, #'basic.get'{queue = ?QNAME}),
    {#'basic.get_ok'{delivery_tag = TagB}, _} =
        amqp_channel:call(Ch, #'basic.get'{queue = ?QNAME}),
    amqp_channel:cast(Ch, #'basic.reject'{delivery_tag = TagA, requeue = true}),
    restart(B),
    ok = sync(C, ?QNAME),
    amqp_channel:cast(Ch, #'basic.reject'{delivery_tag = TagB, requeue = true}),
    consume(Ch, ?QNAME, 2),

    ok.

publish(Ch, QName, Count) ->
    [amqp_channel:call(Ch,
                       #'basic.publish'{routing_key = QName},
                       #amqp_msg{props   = #'P_basic'{delivery_mode = 2},
                                 payload = list_to_binary(integer_to_list(I))})
     || I <- lists:seq(1, Count)],
    amqp_channel:wait_for_confirms(Ch).

consume(Ch, QName, Count) ->
    amqp_channel:subscribe(Ch, #'basic.consume'{queue = QName, no_ack = true},
                           self()),
    CTag = receive #'basic.consume_ok'{consumer_tag = C} -> C end,
    [begin
         Exp = list_to_binary(integer_to_list(I)),
         receive {#'basic.deliver'{consumer_tag = CTag},
                  #amqp_msg{payload = Exp}} ->
                 ok
         after 500 ->
                 exit(timeout)
         end
     end|| I <- lists:seq(1, Count)],
    #'queue.declare_ok'{message_count = 0}
        = amqp_channel:call(Ch, #'queue.declare'{queue   = QName,
                                                 durable = true}),
    amqp_channel:call(Ch, #'basic.cancel'{consumer_tag = CTag}),
    ok.

fetch(Ch, QName, Count) ->
    [{#'basic.get_ok'{}, _} =
         amqp_channel:call(Ch, #'basic.get'{queue = QName}) ||
        _ <- lists:seq(1, Count)],
    ok.

restart(Node) ->
    rabbit_ha_test_utils:stop_app(Node),
    rabbit_ha_test_utils:start_app(Node).

sync(Node, QName) ->
    case sync_nowait(Node, QName) of
        ok -> wait_for_sync(Node, QName),
              ok;
        R  -> R
    end.

sync_nowait(Node, QName) -> action(Node, sync_queue, QName).
sync_cancel(Node, QName) -> action(Node, cancel_sync_queue, QName).

wait_for_sync(Node, QName) ->
    slave_synchronization_SUITE:wait_for_sync_status(true, Node, QName).

action(Node, Action, QName) ->
    rabbit_ha_test_utils:control_action(
      Action, Node, [binary_to_list(QName)], [{"-p", "/"}]).

queue(Node, QName) ->
    QNameRes = rabbit_misc:r(<<"/">>, queue, QName),
    {ok, Q} = rpc:call(Node, rabbit_amqqueue, lookup, [QNameRes]),
    Q.

wait_for_syncing(Node, QName, Target) ->
    case state(Node, QName) of
        {{syncing, _}, _} -> ok;
        {running, Target} -> synced_already;
        _                 -> timer:sleep(100),
                             wait_for_syncing(Node, QName, Target)
    end.

wait_for_running(Node, QName) ->
    case state(Node, QName) of
        {running, _} -> ok;
        _            -> timer:sleep(100),
                        wait_for_running(Node, QName)
    end.

state(Node, QName) ->
    [{state, State}, {synchronised_slave_pids, Pids}] =
        rpc:call(Node, rabbit_amqqueue, info,
                 [queue(Node, QName), [state, synchronised_slave_pids]]),
    {State, length(Pids)}.
