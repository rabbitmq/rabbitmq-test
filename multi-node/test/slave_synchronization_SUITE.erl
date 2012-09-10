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
-module(slave_synchronization_SUITE).

-include_lib("amqp_client/include/amqp_client.hrl").

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1,
         slave_synchronization/1, slave_synchronization_ttl/1]).

suite() -> [{timetrap, systest:settings("time_traps.ha_cluster_SUITE")}].

all() ->
    [slave_synchronization, slave_synchronization_ttl].

init_per_suite(Config) ->
    timer:start(),
    Config.

end_per_suite(_Config) ->
    ok.

slave_synchronization(Config) ->
    {_Cluster, [{{Master, _MRef}, {_Connection,      Channel}},
                {{Slave,  _SRef}, {_SlaveConnection, _SlaveChannel}},
                _Unused]} =
        rabbit_ha_test_utils:cluster_members(Config),

    Queue = <<"test">>,
    MirrorArgs = rabbit_ha_test_utils:mirror_args([Master, Slave]),
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel, #'queue.declare'{queue       = Queue,
                                                    auto_delete = false,
                                                    arguments   = MirrorArgs}),

    %% The comments on the right are the queue length and the pending acks on
    %% the master.
    rabbit_ha_test_utils:stop_app(Slave),

    %% We get and ack one message when the slave is down, and check that when we
    %% start the slave it's not marked as synced until ack the message.  We also
    %% publish another message when the slave is up.
    send_dummy_message(Channel, Queue),                                 % 1 - 0
    {#'basic.get_ok'{delivery_tag = Tag1}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 0 - 1

    rabbit_ha_test_utils:start_app(Slave),

    slave_unsynced(Master, Queue),
    send_dummy_message(Channel, Queue),                                 % 1 - 1
    slave_unsynced(Master, Queue),

    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag1}),      % 1 - 0

    timer:sleep(1000),
    slave_synced(Master, Queue),

    %% We restart the slave and we send a message, so that the slave will only
    %% have one of the messages.
    rabbit_ha_test_utils:stop_app(Slave),
    rabbit_ha_test_utils:start_app(Slave),

    send_dummy_message(Channel, Queue),                                 % 2 - 0

    slave_unsynced(Master, Queue),

    %% We reject the message that the slave doesn't have, and verify that it's
    %% still unsynced
    {#'basic.get_ok'{delivery_tag = Tag2}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 1 - 1
    slave_unsynced(Master, Queue),
    amqp_channel:cast(Channel, #'basic.reject'{ delivery_tag = Tag2,
                                                requeue      = true }), % 2 - 0
    slave_unsynced(Master, Queue),
    {#'basic.get_ok'{delivery_tag = Tag3}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 1 - 1
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag3}),      % 1 - 0
    timer:sleep(1000),
    slave_synced(Master, Queue),
    {#'basic.get_ok'{delivery_tag = Tag4}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 0 - 1
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag4}),      % 0 - 0
    slave_synced(Master, Queue).

slave_synchronization_ttl(Config) ->
    {_Cluster, [{{Master, _MRef}, {_Connection,      Channel}},
                {{Slave,  _SRef}, {_SlaveConnection, _SlaveChannel}},
                {{DLX,    _DRef}, {_DLXConnection,   DLXChannel}}]} =
        rabbit_ha_test_utils:cluster_members(Config),

    %% We declare a DLX queue to wait for messages to be TTL'ed
    DLXQueue = <<"dlx-queue">>,
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel, #'queue.declare'{queue       = DLXQueue,
                                                    auto_delete = false}),

    Queue = <<"test">>,
    %% Sadly we need fairly high numbers for the TTL because starting/stopping
    %% nodes takes a fair amount of time.
    Args = rabbit_ha_test_utils:mirror_args([Master, Slave]) ++
        [{<<"x-message-ttl">>, long, 1000},
         {<<"x-dead-letter-exchange">>, longstr, <<>>},
         {<<"x-dead-letter-routing-key">>, longstr, DLXQueue}],
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel, #'queue.declare'{queue       = Queue,
                                                    auto_delete = false,
                                                    arguments   = Args}),

    timer:sleep(1000),
    slave_synced(Master, Queue),

    %% All unknown
    rabbit_ha_test_utils:stop_app(Slave),
    send_dummy_message(Channel, Queue),
    send_dummy_message(Channel, Queue),
    rabbit_ha_test_utils:start_app(Slave),
    slave_unsynced(Master, Queue),
    wait_for_messages(DLXQueue, DLXChannel, 2),
    timer:sleep(1000),
    slave_synced(Master, Queue),

    %% 1 unknown, 1 known
    rabbit_ha_test_utils:stop_app(Slave),
    send_dummy_message(Channel, Queue),
    rabbit_ha_test_utils:start_app(Slave),
    slave_unsynced(Master, Queue),
    send_dummy_message(Channel, Queue),
    slave_unsynced(Master, Queue),
    wait_for_messages(DLXQueue, DLXChannel, 2),
    timer:sleep(1000),
    slave_synced(Master, Queue),

    %% %% both known
    send_dummy_message(Channel, Queue),
    send_dummy_message(Channel, Queue),
    slave_synced(Master, Queue),
    wait_for_messages(DLXQueue, DLXChannel, 2),
    timer:sleep(1000),
    slave_synced(Master, Queue),

    ok.

send_dummy_message(Channel, Queue) ->
    Payload = <<"foo">>,
    Publish = #'basic.publish'{exchange = <<>>, routing_key = Queue},
    amqp_channel:cast(Channel, Publish, #amqp_msg{payload = Payload}).

slave_pids(Node, Queue) ->
    [[_Name, {synchronised_slave_pids, Pids}]] =
        lists:filter(
          fun ([{name, {resource, <<"/">>, queue, Queue1}}, _SyncPids]) ->
                  Queue1 =:= Queue
          end, rpc:call(Node, rabbit_amqqueue, info_all,
                        [<<"/">>, [name, synchronised_slave_pids]])),
    Pids.

slave_synced(Node, Queue) ->
    1 = length(slave_pids(Node, Queue)).

slave_unsynced(Node, Queue) ->
    0 = length(slave_pids(Node, Queue)).

wait_for_messages(Queue, Channel, N) ->
    Sub = #'basic.consume'{queue = Queue},
    #'basic.consume_ok'{consumer_tag = CTag} = amqp_channel:call(Channel, Sub),
    receive
        #'basic.consume_ok'{} -> ok
    end,
    lists:foreach(
      fun (_) -> receive
                     {#'basic.deliver'{delivery_tag = Tag}, Content} ->
                         amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag})
                 end
      end, lists:seq(1, N)),
    amqp_channel:call(Channel, #'basic.cancel'{consumer_tag = CTag}).
