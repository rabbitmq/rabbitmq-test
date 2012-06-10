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
-module(simple_ha_cluster_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([suite/0, all/0, init_per_suite/1,
         end_per_suite/1, send_and_consumer_around_cluster/1]).

suite() -> [{timetrap, {seconds, 60}}].

all() ->
    [send_and_consumer_around_cluster].

init_per_suite(Config) ->
    timer:start(),
    Config.

end_per_suite(_Config) ->
    ok.

send_and_consumer_around_cluster(Config) ->
    rabbit_ha_test_utils:with_cluster(Config, fun test_send_consume/2).

test_send_consume(Cluster,
                  [{Node1, {_Conn1, Channel1}},
                   {Node2, {_Conn2, Channel2}},
                   {Node3, {_Conn3, Channel3}}]) ->

    %% a quick sanity in the logs/console
    systest_cluster:print_status(Cluster),

    %% Test the nodes policy this time.
    Nodes = [Node1, Node2, Node3],
    MirrorArgs = rabbit_ha_test_utils:mirror_args(Nodes),

    %% declare the queue on the master, mirrored to the two slaves
    #'queue.declare_ok'{queue=Queue} =
        amqp_channel:call(Channel1,
                          #'queue.declare'{auto_delete = false,
                                           arguments   = MirrorArgs}),

    Msgs = 200,

    %% start up a consumer
    ConsumerPid = rabbit_ha_test_consumer:create(Channel2, Queue,
                                                 self(), false, Msgs),

    %% send a bunch of messages from the producer
    ProducerPid = rabbit_ha_test_producer:create(Channel3, Queue,
                                                 self(), false, Msgs),

    %% create a killer for the master - we send a brutal -9 (SIGKILL)
    %% instruction, as that is how the previous implementation worked
    systest_node:kill_after(50, Node1, sigkill),

    %% verify that the consumer got all msgs, or die - the await_response
    %% calls throw an exception if anything goes wrong....
    rabbit_ha_test_consumer:await_response(ConsumerPid),
    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.

