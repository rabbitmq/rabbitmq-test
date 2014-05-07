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
-module(simple_ha).

-compile(export_all).
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-import(rabbit_test_utils, [set_policy/4, a2b/1]).
-import(rabbit_misc, [pget/2]).

rapid_redeclare_with() -> cluster_ab.
rapid_redeclare([CfgA | _]) ->
    Ch = pget(channel, CfgA),
    Queue = <<"ha.all.test">>,
    [begin
         amqp_channel:call(Ch, #'queue.declare'{queue   = Queue,
                                                durable = true}),
         amqp_channel:call(Ch, #'queue.delete'{queue  = Queue})
     end || _I <- lists:seq(1, 20)],
    ok.

consume_survives_stop_with()     -> cluster_abc.
consume_survives_sigkill_with()  -> cluster_abc.
consume_survives_policy_with()   -> cluster_abc.
auto_resume_with()               -> cluster_abc.
auto_resume_no_ccn_client_with() -> cluster_abc.

consume_survives_stop(Cf)     -> consume_survives(Cf, fun stop/2,    true).
consume_survives_sigkill(Cf)  -> consume_survives(Cf, fun sigkill/2, true).
consume_survives_policy(Cf)   -> consume_survives(Cf, fun policy/2,  true).
auto_resume(Cf)               -> consume_survives(Cf, fun sigkill/2, false).
auto_resume_no_ccn_client(Cf) -> consume_survives(Cf, fun sigkill/2, false,
                                                  false).

confirms_survive_stop_with()    -> cluster_abc.
confirms_survive_sigkill_with() -> cluster_abc.
confirms_survive_policy_with()  -> cluster_abc.

confirms_survive_stop(Cf)    -> confirms_survive(Cf, fun stop/2).
confirms_survive_sigkill(Cf) -> confirms_survive(Cf, fun sigkill/2).
confirms_survive_policy(Cf)  -> confirms_survive(Cf, fun policy/2).

%% %%----------------------------------------------------------------------------

consume_survives(Nodes, DeathFun, CancelOnFailover) ->
    consume_survives(Nodes, DeathFun, CancelOnFailover, true).

consume_survives([CfgA, CfgB, CfgC] = Nodes,
                 DeathFun, CancelOnFailover, CCNSupported) ->
    Msgs = rabbit_test_configs:cover_work_factor(20000, CfgA),
    Channel1 = pget(channel, CfgA),
    Channel2 = pget(channel, CfgB),
    Channel3 = pget(channel, CfgC),

    %% declare the queue on the master, mirrored to the two slaves
    Queue = <<"ha.all.test">>,
    amqp_channel:call(Channel1, #'queue.declare'{queue       = Queue,
                                                 auto_delete = false}),

    %% start up a consumer
    ConsCh = case CCNSupported of
                 true  -> Channel2;
                 false -> open_incapable_channel(pget(port, CfgB))
             end,
    ConsumerPid = rabbit_ha_test_consumer:create(
                    ConsCh, Queue, self(), CancelOnFailover, Msgs),

    %% send a bunch of messages from the producer
    ProducerPid = rabbit_ha_test_producer:create(Channel3, Queue,
                                                 self(), false, Msgs),
    DeathFun(a, Nodes),
    %% verify that the consumer got all msgs, or die - the await_response
    %% calls throw an exception if anything goes wrong....
    rabbit_ha_test_consumer:await_response(ConsumerPid),
    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.

confirms_survive([CfgA, CfgB, _CfgC] = Nodes, DeathFun) ->
    Msgs = rabbit_test_configs:cover_work_factor(20000, CfgA),
    Node1Channel = pget(channel, CfgA),
    Node2Channel = pget(channel, CfgB),

    %% declare the queue on the master, mirrored to the two slaves
    Queue = <<"ha.all.test">>,
    amqp_channel:call(Node1Channel,#'queue.declare'{queue       = Queue,
                                                    auto_delete = false,
                                                    durable     = true}),

    %% send a bunch of messages from the producer
    ProducerPid = rabbit_ha_test_producer:create(Node2Channel, Queue,
                                                 self(), true, Msgs),
    DeathFun(a, Nodes),
    rabbit_ha_test_producer:await_response(ProducerPid),
    ok.

stop(Name, Nodes)    -> rabbit_test_utils:kill_after(50, Name, Nodes, stop).
sigkill(Name, Nodes) -> rabbit_test_utils:kill_after(50, Name, Nodes, sigkill).
policy(Name, [H|T])  -> Nodes = [a2b(pget(node, Cfg)) || Cfg <- T],
                        Node = rabbit_test_utils:find(Name, node, [H|T]),
                        set_policy(Node, <<"^ha.all.">>, <<"nodes">>, Nodes).

open_incapable_channel(NodePort) ->
    Props = [{<<"capabilities">>, table, []}],
    {ok, ConsConn} =
        amqp_connection:start(#amqp_params_network{port              = NodePort,
                                                   client_properties = Props}),
    {ok, Ch} = amqp_connection:open_channel(ConsConn),
    Ch.
