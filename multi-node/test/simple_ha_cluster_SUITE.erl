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
-module(simple_ha_cluster_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1,
         consume_survives_stop/1, consume_survives_sigkill/1,
         consume_survives_policy/1, auto_resume/1,
         confirms_survive_stop/1, confirms_survive_sigkill/1,
         confirms_survive_policy/1,
         rapid_redeclare/1]).

-import(rabbit_ha_test_utils, [set_policy/4, a2b/1, kill_after/4]).

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

rapid_redeclare(Config) ->
    {_, [{_, {_, Ch}}|_]} = rabbit_ha_test_utils:cluster_members(Config),
    Queue = <<"ha.all.test">>,
    [begin
         amqp_channel:call(Ch, #'queue.declare'{queue  = Queue,
                                                durable = true}),
         amqp_channel:call(Ch, #'queue.delete'{queue  = Queue})
     end || _I <- lists:seq(1, 20)],
    ok.

consume_survives_stop(Cf)    -> consume_survives(Cf, fun stop/3,    true).
consume_survives_sigkill(Cf) -> consume_survives(Cf, fun sigkill/3, true).
consume_survives_policy(Cf)  -> consume_survives(Cf, fun policy/3,  true).
auto_resume(Cf)              -> consume_survives(Cf, fun sigkill/3, false).

confirms_survive_stop(Cf)    -> confirms_survive(Cf, fun stop/3).
confirms_survive_sigkill(Cf) -> confirms_survive(Cf, fun sigkill/3).
confirms_survive_policy(Cf)  -> confirms_survive(Cf, fun policy/3).

%%----------------------------------------------------------------------------

consume_survives(Config, DeathFun, CancelOnFailover) ->
    {_Cluster,
      [{{Node1, Node1Pid}, {_Conn1, Channel1}},
       {{Node2, _Node2Pid}, {_Conn2, Channel2}},
       {{Node3, _Node3Pid}, {_Conn3, Channel3}}
            ]} = rabbit_ha_test_utils:cluster_members(Config),

    %% declare the queue on the master, mirrored to the two slaves
    Queue = <<"ha.all.test">>,
    amqp_channel:call(Channel1, #'queue.declare'{queue       = Queue,
                                                 auto_delete = false}),

    Msgs = systest:settings("message_volumes.send_consume"),

    %% start up a consumer
    ConsumerPid = rabbit_ha_test_consumer:create(
                    Channel2, Queue, self(), CancelOnFailover, Msgs),

    %% send a bunch of messages from the producer
    ProducerPid = rabbit_ha_test_producer:create(Channel3, Queue,
                                                 self(), false, Msgs),
    DeathFun(Node1, Node1Pid, [Node2, Node3]),
    %% verify that the consumer got all msgs, or die - the await_response
    %% calls throw an exception if anything goes wrong....
    rabbit_ha_test_consumer:await_response(ConsumerPid),
    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.

confirms_survive(Config, DeathFun) ->
    {_Cluster,
        [{{Node1, Node1Pid}, {_Node1Connection, Node1Channel}},
         {{Node2, _Node2Pid},{_Node2Connection, Node2Channel}}|_]
            } = rabbit_ha_test_utils:cluster_members(Config),

    %% declare the queue on the master, mirrored to the two slaves
    Queue = <<"ha.all.test">>,
    amqp_channel:call(Node1Channel,#'queue.declare'{queue       = Queue,
                                                    auto_delete = false,
                                                    durable     = true}),

    Msgs = systest:settings("message_volumes.producer_confirms"),

    %% send a bunch of messages from the producer
    ProducerPid = rabbit_ha_test_producer:create(Node2Channel, Queue,
                                                 self(), true, Msgs),
    DeathFun(Node1, Node1Pid, [Node2]),
    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.


stop(Node, NodePid, _Rest)    -> kill_after(50, Node, NodePid, stop).
sigkill(Node, NodePid, _Rest) -> kill_after(50, Node, NodePid, sigkill).
policy(Node, _NodePid, Rest)  -> Nodes = [a2b(N) || N <- Rest],
                                 set_policy(
                                   Node, <<"^ha.all.">>, <<"nodes">>, Nodes).
