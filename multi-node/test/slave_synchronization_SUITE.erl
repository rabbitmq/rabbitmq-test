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
         slave_synchronization/1]).

suite() -> [{timetrap, systest:settings("time_traps.ha_cluster_SUITE")}].

all() ->
    [slave_synchronization].

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

    send_dummy_message(Channel, Queue),                                 % 2 - 0

    rabbit_ha_test_utils:stop_app(Slave),
    rabbit_ha_test_utils:start_app(Slave),

    slave_unsynced(Master),
    {#'basic.get_ok'{delivery_tag = Tag2}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 1 - 1
    slave_unsynced(Master),
    amqp_channel:cast(Channel, #'basic.reject'{ delivery_tag = Tag2,
                                                requeue      = true }), % 2 - 0
    slave_unsynced(Master),
    {#'basic.get_ok'{delivery_tag = Tag3}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 1 - 1
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag3}),      % 1 - 0
    slave_unsynced(Master),
    {#'basic.get_ok'{delivery_tag = Tag4}, _} =
        amqp_channel:call(Channel, #'basic.get'{queue = Queue}),        % 0 - 1
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = Tag4}),      % 0 - 0

    timer:sleep(1000),
    slave_synced(Master).

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
