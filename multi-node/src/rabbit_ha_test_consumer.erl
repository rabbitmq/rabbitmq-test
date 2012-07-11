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
-module(rabbit_ha_test_consumer).

-include_lib("amqp_client/include/amqp_client.hrl").

-export([await_response/1, await_response/2, create/5, start/6]).

await_response(ConsumerPid) ->
    await_response(ConsumerPid, 60000).

await_response(ConsumerPid, Timeout) ->
    case rabbit_ha_test_utils:await_response(ConsumerPid, Timeout) of
        {error, timeout} -> throw(lost_contact_with_consumer);
        {error, Reason}  -> error(Reason);
        ok               -> ok
    end.

create(Channel, Queue, TestPid, NoAck, ExpectingMsgs) ->
    ConsumerPid = spawn(?MODULE, start, [TestPid, Channel, Queue, NoAck,
                                         ExpectingMsgs + 1, ExpectingMsgs]),
    amqp_channel:subscribe(Channel,
                           #'basic.consume'{queue    = Queue,
                                            no_local = false,
                                            no_ack   = NoAck},
                           ConsumerPid),
    ConsumerPid.

start(TestPid, _Channel, _Queue, _NoAck, _LowestSeen, 0) ->
    consumer_reply(TestPid, ok);
start(TestPid, Channel, Queue, NoAck, LowestSeen, MsgsToConsume) ->
    receive
        #'basic.consume_ok'{} ->
            start(TestPid, Channel, Queue, NoAck,
                  LowestSeen, MsgsToConsume);
        {Delivery = #'basic.deliver'{ redelivered = Redelivered },
         #amqp_msg{payload = Payload}} ->
            MsgNum = list_to_integer(binary_to_list(Payload)),

            maybe_ack(Delivery, Channel, NoAck),

            %% we can receive any message we've already seen and,
            %% because of the possibility of multiple requeuings, we
            %% might see these messages in any order. If we are seeing
            %% a message again, we don't decrement the MsgsToConsume
            %% counter.
            if
                MsgNum + 1 == LowestSeen ->
                    start(TestPid, Channel, Queue,
                             NoAck, MsgNum, MsgsToConsume - 1);
                MsgNum >= LowestSeen ->
                    true = Redelivered, %% ASSERTION
                    start(TestPid, Channel, Queue,
                             NoAck, LowestSeen, MsgsToConsume);
                true ->
                    %% We received a message we haven't seen before,
                    %% but it is not the next message in the expected
                    %% sequence.
                    consumer_reply(TestPid,
                                   {error, {unexpected_message, MsgNum}})
            end;
        #'basic.cancel'{} ->
            resubscribe(TestPid, Channel, Queue, NoAck,
                        LowestSeen, MsgsToConsume)
    after
        10000 ->
            consumer_reply(TestPid,
                           {error, {expecting_more_messages, MsgsToConsume}})
    end.

%%
%% Private API
%%

resubscribe(TestPid, Channel, Queue, NoAck, LowestSeen, MsgsToConsume) ->
    amqp_channel:subscribe(Channel,
                           #'basic.consume'{queue    = Queue,
                                            no_local = false,
                                            no_ack   = NoAck},
                           self()),

    ok = receive #'basic.consume_ok'{} -> ok
         after 200 -> missing_consume_ok
         end,

    start(TestPid, Channel, Queue, NoAck, LowestSeen, MsgsToConsume).

maybe_ack(_Delivery, _Channel, true) ->
    ok;
maybe_ack(#'basic.deliver'{delivery_tag = DeliveryTag}, Channel, false) ->
    amqp_channel:call(Channel, #'basic.ack'{delivery_tag = DeliveryTag}),
    ok.

consumer_reply(TestPid, Reply) ->
    TestPid ! {self(), Reply}.
