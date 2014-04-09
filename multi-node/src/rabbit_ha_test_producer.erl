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
-module(rabbit_ha_test_producer).

-export([await_response/1, await_response/2, start/5, create/5]).

-include_lib("amqp_client/include/amqp_client.hrl").

await_response(ProducerPid) ->
    await_response(ProducerPid, infinity).

await_response(ProducerPid, Timeout) ->
    systest:log("waiting for producer pid ~p (timeout = ~p)~n",
                [ProducerPid, Timeout]),
    case rabbit_ha_test_utils:await_response(ProducerPid, Timeout) of
        ok                -> ok;
        {error, _} = Else -> ct:fail(Else);
        Else              -> ct:fail({weird_response, Else})
    end.

create(Channel, Queue, TestPid, Confirm, MsgsToSend) ->
    ProducerPid = spawn_link(?MODULE, start, [Channel, Queue, TestPid,
                                              Confirm, MsgsToSend]),
    StartTimeout = 10000,
    case rabbit_ha_test_utils:await_response(ProducerPid, StartTimeout) of
        started -> ProducerPid;
        Other   -> throw({producer_not_started, Other})
    end.

start(Channel, Queue, TestPid, Confirm, MsgsToSend) ->
    ConfirmState =
        case Confirm of
            true  -> amqp_channel:register_confirm_handler(Channel, self()),
                     #'confirm.select_ok'{} =
                         amqp_channel:call(Channel, #'confirm.select'{}),
                     gb_trees:empty();
            false -> none
        end,
    TestPid ! {self(), started},
    producer(Channel, Queue, TestPid, ConfirmState, MsgsToSend).

%%
%% Private API
%%

producer(_Channel, _Queue, TestPid, none, 0) ->
    TestPid ! {self(), ok};
producer(_Channel, _Queue, TestPid, ConfirmState, 0) ->
    Msg = case drain_confirms(no_nacks, ConfirmState) of
              no_nacks    -> ok;
              nacks       -> {error, received_nacks};
              {Nacks, CS} -> {error, {missing_confirms, Nacks,
                                      lists:sort(gb_trees:keys(CS))}}
          end,
    TestPid ! {self(), Msg};

producer(Channel, Queue, TestPid, ConfirmState, MsgsToSend) ->
    Method = #'basic.publish'{exchange    = <<"">>,
                              routing_key = Queue,
                              mandatory   = false,
                              immediate   = false},

    ConfirmState1 = maybe_record_confirm(ConfirmState, Channel, MsgsToSend),

    systest:log("publishing msg ~p on ~p~n", [MsgsToSend, Channel]),
    amqp_channel:call(Channel, Method,
                      #amqp_msg{props = #'P_basic'{delivery_mode = 2},
                                payload = list_to_binary(
                                            integer_to_list(MsgsToSend))}),

    producer(Channel, Queue, TestPid, ConfirmState1, MsgsToSend - 1).

maybe_record_confirm(none, _, _) ->
    none;
maybe_record_confirm(ConfirmState, Channel, MsgsToSend) ->
    SeqNo = amqp_channel:next_publish_seqno(Channel),
    systest:log("acquired next seqno ~p from channel ~p~n", [SeqNo, Channel]),
    gb_trees:insert(SeqNo, MsgsToSend, ConfirmState).

drain_confirms(Nacks, ConfirmState) ->
    case gb_trees:is_empty(ConfirmState) of
        true  -> Nacks;
        false -> systest:log("awaiting basic.ack/nack~n", []),
                 receive
                     #'basic.ack'{delivery_tag = DeliveryTag,
                                  multiple     = IsMulti} ->
                         drain_confirms(Nacks,
                                        delete_confirms(DeliveryTag, IsMulti,
                                                        ConfirmState));
                     #'basic.nack'{delivery_tag = DeliveryTag,
                                   multiple     = IsMulti} ->
                         drain_confirms(nacks,
                                        delete_confirms(DeliveryTag, IsMulti,
                                                        ConfirmState))
                 after
                     60000 -> {Nacks, ConfirmState}
                 end
    end.

delete_confirms(DeliveryTag, false, ConfirmState) ->
    gb_trees:delete(DeliveryTag, ConfirmState);
delete_confirms(DeliveryTag, true, ConfirmState) ->
    multi_confirm(DeliveryTag, ConfirmState).

multi_confirm(DeliveryTag, ConfirmState) ->
    case gb_trees:is_empty(ConfirmState) of
        true  -> ConfirmState;
        false -> {Key, _, ConfirmState1} = gb_trees:take_smallest(ConfirmState),
                 case Key =< DeliveryTag of
                     true  -> multi_confirm(DeliveryTag, ConfirmState1);
                     false -> ConfirmState
                 end
    end.
