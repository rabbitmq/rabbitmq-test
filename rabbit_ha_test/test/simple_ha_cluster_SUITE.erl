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
         end_per_suite/1,
         send_and_consumer_around_cluster/1,
         killing_multiple_intermediate_nodes/1]).

%% NB: it takes almost a minute to start and cluster 6 nodes
%% used in this test case, so a 3 minute time trap seems reasonable
suite() -> [{timetrap, {minutes, 3}}].

all() ->
    systest_suite:export_all(?MODULE).

init_per_suite(Config) ->
    timer:start(),
    Config.
end_per_suite(_Config) ->
    ok.

send_and_consumer_around_cluster(Config) ->
    rabbit_ha_test_utils:with_cluster(Config, fun test_send_consume/2).

%% TODO: investigate *why* setting the timetrap here doesn't override
%% a suite setting of {seconds, 60}, as we don't necessarily want all
%% the test cases to be given so generous a limit

killing_multiple_intermediate_nodes() ->
    [{timetrap, {minutes, 3}}].

killing_multiple_intermediate_nodes(Config) ->
    rabbit_ha_test_utils:with_cluster(Config, fun test_multi_kill/2).

%% Private Implementation

test_send_consume(Cluster,
                  [{Node1, {_Conn1, Channel1}},
                   {Node2, {_Conn2, Channel2}},
                   {Node3, {_Conn3, Channel3}}]) ->

    %% Test the nodes policy this time.
    Nodes = [Node1, Node2, Node3],
    ct:pal("reading status info.....~n"),
    [ct:pal("~p: ~p~n", [P, R]) || {P, R} <- [begin
                                                  {N,
                                                   rpc:call(N, rabbit_mnesia,
                                                            status, [])}
                                              end || N <- Nodes]],
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

%% TODO: as per this afternoon's conversation with Simon, figure out
%% how to rename the cluster members so as to avoid using the master/slave
%% terminology where it doesn't belong...

test_multi_kill(_Cluster,
                [{Master, {_MasterConnection, MasterChannel}},
                 {Slave1, {_Slave1Connection, _Slave1Channel}},
                 {Slave2, {_Slave2Connection, _Slave2Channel}},
                 {Slave3, {_Slave3Connection, _Slave3Channel}},
                 {_Slave4, {_Slave4Connection, Slave4Channel}},
                 {_Producer, {_ProducerConnection, ProducerChannel}}]) ->

    #'queue.declare_ok'{queue = Queue} =
        amqp_channel:call(MasterChannel,
                #'queue.declare'{
                    auto_delete = false,
                    arguments   = [{<<"x-ha-policy">>, longstr, <<"all">>}]}),

    %% REFACTOR: this seems *highly* timing dependant - the assumption is
    %% that the kill will work quickly enough that there will still be
    %% some messages in-flight the we *must* receive despite the intervening
    %% node deaths. Personally, I'm not enthused by this testing methodology.

    Msgs = 5000,

    ConsumerPid = rabbit_ha_test_consumer:create(Slave4Channel,
                                                 Queue, self(), false, Msgs),

    ProducerPid = rabbit_ha_test_producer:create(ProducerChannel,
                                                 Queue, self(), false, Msgs),

              %% create a killer for the master and the first 3 slaves
    [systest_node:kill_after(Time, Node) || {Node, Time} <-
                                            [{Master, 50},
                                             {Slave1, 100},
                                             {Slave2, 200},
                                             {Slave3, 300}]],

    %% verify that the consumer got all msgs, or die
    rabbit_ha_test_consumer:await_response(ConsumerPid),
    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.
