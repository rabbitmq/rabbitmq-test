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
%% Copyright (c) 2007-2015 Pivotal Software, Inc.  All rights reserved.
%%
-module(channel_operation_timeout).

-compile([export_all]).

-import(rabbit_misc, [pget/2, pget/3]).

-define(CONFIG, [cluster_ab]).
-define(DEFAULT_VHOST, <<"/">>).
-define(QRESOURCE(Q), rabbit_misc:r(?DEFAULT_VHOST, queue, Q)).
-define(TIMEOUT_TEST_MSG,   <<"timeout_test_msg!">>).
-define(DELAY,   25).

-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

%% -----
%% Tests
%% -----
notify_down_all_with() -> ?CONFIG.
notify_down_all(Cfgs = [RabbitCfg, HareCfg]) ->
    Rabbit   = pget(node, RabbitCfg),
    RabbitCh = pget(channel, RabbitCfg),
    HareCh   = pget(channel, HareCfg),

    %% success
    set_channel_operation_timeout_config(Cfgs, 1000),
    configure_bq(Cfgs),
    QCfg0    = qconfig(RabbitCh, <<"q0">>, <<"ex0">>, true, false),
    declare(QCfg0),
    %% Testing rabbit_amqqueue:notify_down_all via rabbit_channel.
    %% Consumer count = 0 after correct channel termination and
    %% notification of queues via delagate:call/3
    true = (0 =/= length(get_consumers(Rabbit, ?DEFAULT_VHOST))),
    amqp_channel:close(RabbitCh),
    0 = length(get_consumers(Rabbit, ?DEFAULT_VHOST)),
    false = is_process_alive(RabbitCh),

    %% fail
    set_channel_operation_timeout_config(Cfgs, 10),
    QCfg2 = qconfig(HareCh, <<"q1">>, <<"ex1">>, true, false),
    declare(QCfg2),
    publish(QCfg2, ?TIMEOUT_TEST_MSG),
    timer:sleep(?DELAY),
    amqp_channel:close(HareCh),
    timer:sleep(?DELAY),
    false = is_process_alive(HareCh),

    stop_all(Cfgs),
    pass.

%% -------------------------
%% Internal helper functions
%% -------------------------
set_channel_operation_timeout_config(Cfgs, Timeout) ->
    [ok = rpc(pget(node, Cfg), application, set_env,
              [rabbit, channel_operation_timeout, Timeout])
     || Cfg <- Cfgs],
    ok.

set_channel_operation_backing_queue(Cfgs) ->
    [ok = rpc(pget(node, Cfg), application, set_env,
              [rabbit, backing_queue_module,
               channel_operation_timeout_test_queue])
     || Cfg <- Cfgs],
    ok.

re_enable_priority_queue(Cfgs) ->
    [ok = rpc(pget(node, Cfg), rabbit_priority_queue, enable, [])
     || Cfg <- Cfgs],
    ok.

add_code_path(Cfgs, Path) ->
    [true = rpc(pget(node, Cfg), code, add_path, [Path])
     || Cfg <- Cfgs],
    ok.

stop_all(Cfgs) ->
    [rpc(pget(node,Cfg), erlang, halt, []) || Cfg <- Cfgs].

declare(QCfg) ->
    QDeclare = #'queue.declare'{queue = Q = pget(name, QCfg), durable = true},
    #'queue.declare_ok'{} = amqp_channel:call(Ch = pget(ch, QCfg), QDeclare),

    ExDeclare =  #'exchange.declare'{exchange = Ex = pget(ex, QCfg)},
    #'exchange.declare_ok'{} = amqp_channel:call(Ch, ExDeclare),
    
    #'queue.bind_ok'{} =
        amqp_channel:call(Ch, #'queue.bind'{queue       = Q,
                                            exchange    = Ex,
                                            routing_key = Q}),
    maybe_subscribe(QCfg).

maybe_subscribe(QCfg) ->
    case pget(consume, QCfg) of
        true ->
            Sub = #'basic.consume'{queue  = pget(name, QCfg)},
            Ch  = pget(ch, QCfg),
            Del = pget(deliver, QCfg),
            amqp_channel:subscribe(Ch, Sub,
                                   spawn(fun() -> consume(Ch, Del) end));
        _ ->  ok
    end.

consume(_Ch, false) -> receive_nothing();
consume(Ch, Deliver = true) ->
    receive
        {#'basic.deliver'{}, _Msg} ->
            consume(Ch, Deliver)
    end.

publish(QCfg, Msg) ->
    Publish = #'basic.publish'{exchange = pget(ex, QCfg),
                               routing_key = pget(name, QCfg)},
    amqp_channel:call(pget(ch, QCfg), Publish,
                      #amqp_msg{payload = Msg}).

get_consumers(Node, VHost) when is_atom(Node),
                                is_binary(VHost) ->
    rpc(Node, rabbit_amqqueue, consumers_all, [VHost]).

amqqueue(Q, Node) ->
    get_amqqueue(?QRESOURCE(Q), rpc(Node, rabbit_amqqueue, list, [])).

get_amqqueue(Q, []) -> throw({not_found, Q});
get_amqqueue(Q, [AMQQ = #amqqueue{name = Q} | _]) -> AMQQ;
get_amqqueue(Q, [_| Rem]) -> get_amqqueue(Q, Rem).

qconfig(Ch, Name, Ex, Consume, Deliver) ->
    [{ch, Ch}, {name, Name}, {ex,Ex}, {consume, Consume}, {deliver, Deliver}].

receive_nothing() ->
    receive
    after infinity -> void
    end.

unhandled_req(Fun) ->
    try
        Fun()
    catch
        exit:{{shutdown,{_, ?NOT_FOUND, _}}, _} -> ok;
        _:Reason                                -> {error, Reason}
    end.

configure_bq(Cfgs) ->
    TestEbin = os:getenv("RABBITMQ_TEST_DIR") ++ "/test",
    ok       = set_channel_operation_backing_queue(Cfgs),
    ok       = re_enable_priority_queue(Cfgs),
    ok       = add_code_path(Cfgs, TestEbin).

rpc(N, M, F, A) when is_list(A) ->
    rpc:call(N, M, F, A).
