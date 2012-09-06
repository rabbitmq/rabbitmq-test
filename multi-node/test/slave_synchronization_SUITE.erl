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

    slave_unsynced(Master),
    send_dummy_message(Channel, Queue),                                 % 1 - 1
    slave_unsynced(Master),

    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag1}),      % 1 - 0

    timer:sleep(1000),
    slave_synced(Master),

    %% We restart the slave and we send a message, so that the slave will only
    %% have one of the messages.
    rabbit_ha_test_utils:stop_app(Slave),
    rabbit_ha_test_utils:start_app(Slave),

    send_dummy_message(Channel, Queue),                                 % 2 - 0

    slave_unsynced(Master),

    %% We reject the message that the slave doesn't have, and verify that it's
    %% still unsynced
    {#'basic.get_ok'{delivery_tag = Tag2}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 1 - 1
    slave_unsynced(Master),
    amqp_channel:cast(Channel, #'basic.reject'{ delivery_tag = Tag2,
                                                requeue      = true }), % 2 - 0
    slave_unsynced(Master),
    {#'basic.get_ok'{delivery_tag = Tag3}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 1 - 1
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag3}),      % 1 - 0
    timer:sleep(1000),
    slave_synced(Master),
    {#'basic.get_ok'{delivery_tag = Tag4}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 0 - 1
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag4}),      % 0 - 0
    slave_synced(Master).

slave_synchronization_ttl(Config) ->
    {_Cluster, [{{Master, _MRef}, {_Connection,      Channel}},
                {{Slave,  _SRef}, {_SlaveConnection, _SlaveChannel}},
                _Unused]} =
        rabbit_ha_test_utils:cluster_members(Config),

    Queue = <<"test">>,
    %% Sadly we need fairly high numbers for the TTL because starting/stopping
    %% nodes takes a fair amount of time.
    Args = rabbit_ha_test_utils:mirror_args([Master, Slave]) ++
        [{<<"x-message-ttl">>, long, 1000}],
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel, #'queue.declare'{queue       = Queue,
                                                    auto_delete = false,
                                                    arguments   = Args}),

    timer:sleep(1000),
    slave_synced(Master),

    %% All unknown
    rabbit_ha_test_utils:stop_app(Slave),
    send_dummy_message(Channel, Queue),
    send_dummy_message(Channel, Queue),
    rabbit_ha_test_utils:start_app(Slave),
    slave_unsynced(Master),
    timer:sleep(2000),
    slave_synced(Master),

    %% 1 unknown, 1 known
    rabbit_ha_test_utils:stop_app(Slave),
    send_dummy_message(Channel, Queue),
    rabbit_ha_test_utils:start_app(Slave),
    slave_unsynced(Master),
    send_dummy_message(Channel, Queue),
    slave_unsynced(Master),
    timer:sleep(2000),
    slave_synced(Master),

    %% both known
    send_dummy_message(Channel, Queue),
    send_dummy_message(Channel, Queue),
    slave_synced(Master),
    timer:sleep(2000),
    slave_synced(Master),

    ok.

send_dummy_message(Channel, Queue) ->
    Payload = <<"foo">>,
    Publish = #'basic.publish'{exchange = <<>>, routing_key = Queue},
    amqp_channel:cast(Channel, Publish, #amqp_msg{payload = Payload}).

slave_pids(Node) ->
    [[{synchronised_slave_pids, Pids}]] =
        rpc:call(Node, rabbit_amqqueue, info_all,
                 [<<"/">>, [synchronised_slave_pids]]),
    Pids.

slave_synced(Node) ->
    1 = length(slave_pids(Node)).

slave_unsynced(Node) ->
    0 = length(slave_pids(Node)).
