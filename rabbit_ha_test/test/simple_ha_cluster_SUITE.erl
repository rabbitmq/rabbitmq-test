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
suite() -> [{timetrap, {seconds, 100}}].

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

    Msgs = 2000,

    %% send a bunch of messages from the producer
    ProducerPid = rabbit_ha_test_producer:create(ProducerChannel, Queue,
                                                 self(), true, Msgs),

    %% create a killer for the master
    systest_node:kill_after(50, Master),

    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.

restarted_master_honours_declarations() ->
    %% NB: up to 1.5 mins to fully cluster the nodes
    [{timetrap, {minutes, 5}}].

restarted_master_honours_declarations(Config) ->
    %% NB: this test case is not auto-clustered (we use a hook function in
    %% the rabbit_ha_test_utils module), because we need to perform a very
    %% closely controlled restart and rejoin procedure in this instance.
    process_flag(trap_exit, true),
    rabbit_ha_test_utils:with_cluster(
        Config,
        fun(Cluster,
            [{{Master,   MRef}, {MasterConnection,    MasterChannel}},
             {{Producer, PRef}, {_ProducerConnection, _ProducerChannel}},
             {{Slave,    SRef}, {_SlaveConnection,    _SlaveChannel}}]) ->

            MasterNodeConfig = systest_node:user_data(MRef),
            Queue = <<"ha-test-restarting-master">>,
            MirrorArgs = rabbit_ha_test_utils:mirror_args([Master,
                                                           Producer, Slave]),
            #'queue.declare_ok'{} =
                    amqp_channel:call(MasterChannel,
                        #'queue.declare'{queue       = Queue,
                                         auto_delete = false,
                                         arguments   = MirrorArgs}),

            %% restart master
            rabbit_ha_test_utils:amqp_close(MasterChannel, MasterConnection),

            {ok, {Master, NewMRef}} =
                    systest_cluster:restart_node(Cluster, MRef),
            rabbit_ha_test_utils:cluster_with(Master, [Producer]),

            %% retire other members of the cluster
            systest_node:stop_and_wait(PRef),
            systest_node:stop_and_wait(SRef),

            NewConn = rabbit_ha_test_utils:open_connection(5672),
            NewChann = rabbit_ha_test_utils:open_channel(NewConn),

            rabbit_control_main:action(list_queues, Master,
                                       [], [{"-p", "/"}], fun ct:pal/2),

            %% the master must refuse redeclaration with different parameters
            try
                amqp_channel:call(NewChann,
                        #'queue.declare'{queue = Queue}) of
                    #'queue.declare_ok'{} ->
                        ct:fail("Expected exception ~p wasn't thrown~n",
                                [?PRECONDITION_FAILED])
            catch
                exit:{{shutdown, {server_initiated_close,
                        ?PRECONDITION_FAILED, _Bin}}, _Rest} -> ok
            after
                rabbit_ha_test_utils:amqp_close(NewChann, NewConn)
            end
        end).

