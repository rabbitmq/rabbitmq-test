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
%% Copyright (c) 2007-2012 VMware, Inc.  All rights reserved.
%%
-module(rabbit_ha_test_producer).

-export(compile_all).

-include("rabbitmq_ha_test_cluster.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

wait_for_producer_ok(ProducerPid) ->
    ok = receive
             {ProducerPid, ok}    -> ok;
             {ProducerPid, Other} -> Other
         after
             60000 ->
                 {error, lost_contact_with_producer}
         end.

wait_for_producer_start(ProducerPid) ->
    ok = receive
             {ProducerPid, started} -> ok
         after
             10000 ->
                 {error, producer_not_started}
         end.

create_producer(Channel, Queue, TestPid, Confirm, MsgsToSend) ->
    ProducerPid = spawn(?MODULE, start_producer, [Channel, Queue, TestPid,
                                                  Confirm, MsgsToSend]),
    ok = wait_for_producer_start(ProducerPid),
    ProducerPid.



start_producer(Channel, Queue, TestPid, Confirm, MsgsToSend) ->
    ConfirmState =
        case Confirm of
            true ->
                amqp_channel:register_confirm_handler(Channel, self()),
                #'confirm.select_ok'{} =
                    amqp_channel:call(Channel, #'confirm.select'{}),
                gb_trees:empty();
            false ->
                none
        end,
    TestPid ! {self(), started},
    producer(Channel, Queue, TestPid, ConfirmState, MsgsToSend).

producer(_Channel, _Queue, TestPid, ConfirmState, 0) ->
    ConfirmState1 = drain_confirms(ConfirmState),

    case ConfirmState1 of
        none -> TestPid ! {self(), ok};
        ok   -> TestPid ! {self(), ok};
        _    -> TestPid ! {self(), {error, {missing_confirms,
                                            lists:sort(
                                              gb_trees:keys(ConfirmState1))}}}
    end;
producer(Channel, Queue, TestPid, ConfirmState, MsgsToSend) ->
    Method = #'basic.publish'{exchange    = <<"">>,
                              routing_key = Queue,
                              mandatory   = false,
                              immediate   = false},

    ConfirmState1 = maybe_record_confirm(ConfirmState, Channel, MsgsToSend),

    amqp_channel:call(Channel, Method,
                      #amqp_msg{props = #'P_basic'{delivery_mode = 2},
                                payload = list_to_binary(
                                            integer_to_list(MsgsToSend))}),

    producer(Channel, Queue, TestPid, ConfirmState1, MsgsToSend - 1).

maybe_record_confirm(none, _, _) ->
    none;
maybe_record_confirm(ConfirmState, Channel, MsgsToSend) ->
    SeqNo = amqp_channel:next_publish_seqno(Channel),
    gb_trees:insert(SeqNo, MsgsToSend, ConfirmState).

drain_confirms(none) ->
    none;
drain_confirms(ConfirmState) ->
    case gb_trees:is_empty(ConfirmState) of
        true ->
            ok;
        false ->
            receive
                #'basic.ack'{delivery_tag = DeliveryTag,
                             multiple     = IsMulti} ->
                    ConfirmState1 =
                        case IsMulti of
                            false ->
                                gb_trees:delete(DeliveryTag, ConfirmState);
                            true ->
                                multi_confirm(DeliveryTag, ConfirmState)
                        end,
                    drain_confirms(ConfirmState1)
            after
                15000 ->
                    ConfirmState
            end
    end.

multi_confirm(DeliveryTag, ConfirmState) ->
    case gb_trees:is_empty(ConfirmState) of
        true ->
            ConfirmState;
        false ->
            {Key, _, ConfirmState1} = gb_trees:take_smallest(ConfirmState),
            case Key =< DeliveryTag of
                true ->
                    multi_confirm(DeliveryTag, ConfirmState1);
                false ->
                    ConfirmState
            end
    end.


