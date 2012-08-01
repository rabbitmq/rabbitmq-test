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
         producer_confirms_survive_death_of_master/1,
         restarted_master_honours_declarations/0,
         restarted_master_honours_declarations/1]).

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
    MirrorArgs = rabbit_ha_test_utils:mirror_args(Nodes),

    %% declare the queue on the master, mirrored to the two slaves
    #'queue.declare_ok'{queue=Queue} =
        amqp_channel:call(Channel1,
                          #'queue.declare'{auto_delete = false,
                                           arguments   = MirrorArgs}),

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
    #'queue.declare_ok'{queue = Queue} =
        amqp_channel:call(MasterChannel,
                          #'queue.declare'{
                              auto_delete = false,
                              durable     = true,
                              arguments   = [{<<"x-ha-policy">>,
                                                longstr, <<"all">>}]}),

    Msgs = systest:settings("message_volumes.producer_confirms"),

    %% send a bunch of messages from the producer
    ProducerPid = rabbit_ha_test_producer:create(ProducerChannel, Queue,
                                                 self(), true, Msgs),

    systest:kill_after(50, Master),

    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.

restarted_master_honours_declarations() ->
    %% NB: up to 1.5 mins to fully cluster the nodes
    [{timetrap, systest:settings("time_traps.restarted_master")}].

restarted_master_honours_declarations(Config) ->
    {Cluster,
        [{{Master,   MRef}, {MasterConnection,    MasterChannel}},
         {{Producer, PRef}, {_ProducerConnection, _ProducerChannel}},
         {{Slave,    SRef}, {_SlaveConnection,    _SlaveChannel}}]
        } = rabbit_ha_test_utils:cluster_members(Config),

    Queue = <<"ha-test-restarting-master">>,
    MirrorArgs = rabbit_ha_test_utils:mirror_args([Master, Producer, Slave]),
    #'queue.declare_ok'{} = amqp_channel:call(MasterChannel,
                        #'queue.declare'{queue       = Queue,
                                         auto_delete = false,
                                         arguments   = MirrorArgs}),

    %% restart master - we close the connections only to avoid a lot
    %% of noisey sasl logs breaking out in the console! :)
    rabbit_ha_test_utils:amqp_close(MasterChannel, MasterConnection),

    {ok, {Master, _NewMRef}} = systest:restart_process(Cluster, MRef),

    %% NB: when a process restarts, the SUT does *NOT* re-run on_start
    %% hooks for the system as a whole, but it does run on_start, followed
    %% by on_join hooks for the individual process being restarted.
    %% As such, we need to 're-cluster' here, as the clustering operation
    %% run by the framework is attached to the SUT as a whole, so as to ensure
    %% that the cluster is not set up until *after* all the processes
    %% (i.e., nodes) have come online
    rabbit_ha_test_utils:cluster_with(Producer, [Master]),

    %% retire other members of the cluster
    systest:stop_and_wait(PRef),
    systest:stop_and_wait(SRef),

    NewConn = rabbit_ha_test_utils:open_connection(5672),
    NewChann = rabbit_ha_test_utils:open_channel(NewConn),

    %% the master must refuse redeclaration with different parameters
    try amqp_channel:call(NewChann, #'queue.declare'{queue = Queue}) of
        #'queue.declare_ok'{} ->
            ct:fail("Expected exception ~p wasn't thrown~n",
                    [?PRECONDITION_FAILED])
    catch
        exit:{{shutdown, {server_initiated_close,
                ?PRECONDITION_FAILED, _Bin}}, _Rest} -> ok
    after
        rabbit_ha_test_utils:amqp_close(NewChann, NewConn)
    end.

