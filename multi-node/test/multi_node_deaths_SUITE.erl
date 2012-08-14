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
-module(multi_node_deaths_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         killing_multiple_intermediate_nodes/0,
         killing_multiple_intermediate_nodes/1]).

all() ->
    systest_suite:export_all(?MODULE).

init_per_suite(Config) ->
    timer:start(),
    Config.

end_per_suite(_Config) ->
    ok.

killing_multiple_intermediate_nodes() ->
    [{timetrap, systest:settings("time_traps.kill_multi")}].

killing_multiple_intermediate_nodes(Config) ->
    {_Cluster,
         [{{_, Master}, {_MasterConnection, MasterChannel}},
          {{_, Slave1}, {_Slave1Connection, _Slave1Channel}},
          {{_, Slave2}, {_Slave2Connection, _Slave2Channel}},
          {{_, Slave3}, {_Slave3Connection, _Slave3Channel}},
          {_Slave4, {_Slave4Connection, Slave4Channel}},
          {_Producer, {_ProducerConnection, ProducerChannel}}]} =
                    rabbit_ha_test_utils:cluster_members(Config),

    #'queue.declare_ok'{queue = Queue} =
        amqp_channel:call(MasterChannel,
                #'queue.declare'{
                    auto_delete = false,
                    arguments   = [{<<"x-ha-policy">>, longstr, <<"all">>}]}),

    %% TODO: this seems *highly* timing dependant - the assumption being
    %% that the kill will work quickly enough that there will still be
    %% some messages in-flight that we *must* receive despite the intervening
    %% node deaths. It would be nice if we could find a means to do this
    %% in a way that is not actually timing dependent.

    Msgs = systest:settings("message_volumes.kill_multi"),

    ConsumerPid = rabbit_ha_test_consumer:create(Slave4Channel,
                                                 Queue, self(), false, Msgs),

    ProducerPid = rabbit_ha_test_producer:create(ProducerChannel,
                                                 Queue, self(), false, Msgs),

    %% create a killer for the master and the first 3 slaves
    [systest:kill_after(Time, Node) || {Node, Time} <-
                                        [{Master, 50},
                                         {Slave1, 100},
                                         {Slave2, 200},
                                         {Slave3, 300}]],

    %% verify that the consumer got all msgs, or die, or time out
    rabbit_ha_test_producer:await_response(ProducerPid),
    rabbit_ha_test_consumer:await_response(ConsumerPid),
    ok.

