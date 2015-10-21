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

-module(lazy_queue_test).

-compile(export_all).
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-define(QNAME, <<"queue.mode.test">>).
-define(MESSAGE_COUNT, 2000).
-define(CONFIG, [cluster_ab, ha_policy_all]).

-import(rabbit_test_util, [publish/3, set_ha_policy/4, clear_policy/2]).
-import(rabbit_misc, [pget/2]).

declare_args_with() -> ?CONFIG.
declare_args([A, _B]) ->
    Ch = pget(channel, A),
    LQ = <<"lazy-q">>,
    declare(Ch, LQ, [{<<"x-queue-mode">>, longstr, <<"lazy">>}]),
    assert_queue_mode(A, LQ, lazy),

    DQ = <<"default-q">>,
    declare(Ch, DQ, [{<<"x-queue-mode">>, longstr, <<"default">>}]),
    assert_queue_mode(A, DQ, default),

    DQ2 = <<"default-q2">>,
    declare(Ch, DQ2),
    assert_queue_mode(A, DQ2, default),

    passed.

queue_mode_policy_with() -> ?CONFIG.
queue_mode_policy([A, _B]) ->
    set_ha_mode_policy(A, <<"lazy">>),

    Ch = pget(channel, A),

    LQ = <<"lazy-q">>,
    declare(Ch, LQ, [{<<"x-queue-mode">>, longstr, <<"lazy">>}]),
    assert_queue_mode(A, LQ, lazy),

    LQ2 = <<"lazy-q-2">>,
    declare(Ch, LQ2),
    assert_queue_mode(A, LQ2, lazy),

    DQ = <<"default-q">>,
    declare(Ch, DQ, [{<<"x-queue-mode">>, longstr, <<"default">>}]),
    assert_queue_mode(A, DQ, default),

    set_ha_mode_policy(A, <<"default">>),

    ok = wait_for_queue_mode(A, LQ,  lazy, 5000),
    ok = wait_for_queue_mode(A, LQ2, default, 5000),
    ok = wait_for_queue_mode(A, DQ,  default, 5000),

    passed.

publish_consume_with() -> ?CONFIG.
publish_consume([A, _B]) ->
    Ch = pget(channel, A),
    declare(Ch, ?QNAME),

    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    consume(Ch, ?QNAME, ack),
    [assert_delivered(Ch, ack, P) || P <- lists:seq(1, ?MESSAGE_COUNT)],

    set_ha_mode_policy(A, <<"lazy">>),
    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    [assert_delivered(Ch, ack, P) || P <- lists:seq(1, ?MESSAGE_COUNT)],

    set_ha_mode_policy(A, <<"default">>),
    [assert_delivered(Ch, ack, P) || P <- lists:seq(1, ?MESSAGE_COUNT)],

    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    set_ha_mode_policy(A, <<"lazy">>),
    publish(Ch, ?QNAME, ?MESSAGE_COUNT),
    set_ha_mode_policy(A, <<"default">>),
    [assert_delivered(Ch, ack, P) || P <- lists:seq(1, ?MESSAGE_COUNT)],

    set_ha_mode_policy(A, <<"lazy">>),
    [assert_delivered(Ch, ack, P) || P <- lists:seq(1, ?MESSAGE_COUNT)],

    cancel(Ch),

    passed.

%%----------------------------------------------------------------------------

declare(Ch, Q) ->
    declare(Ch, Q, []).

declare(Ch, Q, Args) ->
    amqp_channel:call(Ch, #'queue.declare'{queue     = Q,
                                           durable   = true,
                                           arguments = Args}).

consume(Ch, Q, Ack) ->
    amqp_channel:subscribe(Ch, #'basic.consume'{queue        = Q,
                                                no_ack       = Ack =:= no_ack,
                                                consumer_tag = <<"ctag">>},
                           self()),
    receive
        #'basic.consume_ok'{consumer_tag = <<"ctag">>} ->
             ok
    end.

cancel(Ch) ->
    amqp_channel:call(Ch, #'basic.cancel'{consumer_tag = <<"ctag">>}).

assert_delivered(Ch, Ack, Payload) ->
    PBin = payload2bin(Payload),
    receive
        {#'basic.deliver'{delivery_tag = DTag}, #amqp_msg{payload = PBin2}} ->
            ?assertEqual(PBin, PBin2),
            maybe_ack(Ch, Ack, DTag)
    end.

maybe_ack(Ch, do_ack, DTag) ->
    amqp_channel:cast(Ch, #'basic.ack'{delivery_tag = DTag}),
    DTag;
maybe_ack(_Ch, _, DTag) ->
    DTag.

payload2bin(Int) -> list_to_binary(integer_to_list(Int)).

set_ha_mode_policy(Cfg, Mode) ->
    ok = set_ha_policy(Cfg, <<".*">>, <<"all">>,
                       [{<<"queue-mode">>, Mode}]).


wait_for_queue_mode(_Cfg, _Q, _Mode, Max) when Max < 0 ->
    fail;
wait_for_queue_mode(Cfg, Q, Mode, Max) ->
    case get_queue_mode(Cfg, Q) of
        Mode  -> ok;
        _     -> timer:sleep(100),
                 wait_for_queue_mode(Cfg, Q, Mode, Max - 100)
    end.

assert_queue_mode(Cfg, Q, Expected) ->
    Actual = get_queue_mode(Cfg, Q),
    ?assertEqual(Expected, Actual).

get_queue_mode(Cfg, Q) ->
    QNameRes = rabbit_misc:r(<<"/">>, queue, Q),
    {ok, AMQQueue} =
        rpc:call(pget(node, Cfg), rabbit_amqqueue, lookup, [QNameRes]),
    [{backing_queue_status, Status}] =
        rpc:call(pget(node, Cfg), rabbit_amqqueue, info,
                 [AMQQueue, [backing_queue_status]]),
    proplists:get_value(mode, Status).
