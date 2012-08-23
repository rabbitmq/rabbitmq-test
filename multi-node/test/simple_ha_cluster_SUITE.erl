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
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([suite/0, all/0, init_per_suite/1,
         end_per_suite/1,
         send_consume_survives_node_deaths/1,
         producer_confirms_survive_death_of_master/1]).

%% NB: it can take almost a minute to start and cluster 3 nodes,
%% and then we need time left over to run the actual tests...
suite() -> [{timetrap, systest:settings("time_traps.ha_cluster_SUITE")}].

all() ->
    systest_suite:export_all(?MODULE).

init_per_suite(Config) ->
    timer:start(),
    Config.

end_per_suite(_Config) ->
    ok.

send_consume_survives_node_deaths(Config) ->
    {_Cluster,
      [{{Node1,_}, {_Conn1, Channel1}},
       {{Node2,_}, {_Conn2, Channel2}},
       {{Node3,_}, {_Conn3, Channel3}}
            ]} = rabbit_ha_test_utils:cluster_members(Config),

    %% Test the nodes policy this time.
    Nodes = [Node1, Node2, Node3],
    [ct:log("~p: ~p~n", [P, R]) || {P, R} <- [begin
                                                  {N,
                                                   rpc:call(N, rabbit_mnesia,
                                                            status, [])}
                                              end || N <- Nodes]],
    %% declare the queue on the master, mirrored to the two slaves
    Queue = <<"ha.nodes.test">>,
    amqp_channel:call(Channel1, #'queue.declare'{queue       = Queue,
                                                 auto_delete = false}),

    Msgs = systest:settings("message_volumes.send_consume"),

    %% start up a consumer
    ConsumerPid = rabbit_ha_test_consumer:create(Channel2, Queue,
                                                 self(), false, Msgs),

    %% send a bunch of messages from the producer
    ProducerPid = rabbit_ha_test_producer:create(Channel3, Queue,
                                                 self(), false, Msgs),

    %% create a killer for the master - we send a brutal -9 (SIGKILL)
    %% instruction, as that is how the previous implementation worked
    systest:kill_after(50, Node1, sigkill),

    %% verify that the consumer got all msgs, or die - the await_response
    %% calls throw an exception if anything goes wrong....
    rabbit_ha_test_consumer:await_response(ConsumerPid),
    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.

producer_confirms_survive_death_of_master(Config) ->
    {_Cluster,
        [{{Master, _}, {_MasterConnection, MasterChannel}},
        {{_Producer,_},{_ProducerConnection, ProducerChannel}}|_]
            } = rabbit_ha_test_utils:cluster_members(Config),

    %% declare the queue on the master, mirrored to the two slaves
    Queue = <<"ha.all.test">>,
    amqp_channel:call(MasterChannel,#'queue.declare'{queue       = Queue,
                                                     auto_delete = false,
                                                     durable     = true}),

    Msgs = systest:settings("message_volumes.producer_confirms"),

    %% send a bunch of messages from the producer
    ProducerPid = rabbit_ha_test_producer:create(ProducerChannel, Queue,
                                                 self(), true, Msgs),

    systest:kill_after(50, Master),

    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.
