%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License at
%% http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%% License for the specific language governing rights and limitations
%% under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2011-2015 Pivotal Software, Inc.  All rights reserved.
%%
-module(queue_master_location).

%% These tests use an ABC cluster with each node initialised with
%% a different number of queues. When a queue is declared, different
%% strategies can be applied to determine the queue's master node. Queue
%% location strategies can be applied in the following ways;
%%   1. As policy,
%%   2. As config (in rabbitmq.config),
%%   3. or as part of the queue's declare arguements.
%%
%% Currently supported strategies are;
%%   min-masters : The queue master node is calculated as the one with the
%%                 least bound queues in the cluster.
%%   client-local: The queue master node is the local node from which
%%                 the declaration is being carried out from
%%   random      : The queue master node is randomly selected.
%%

-compile(export_all).
-import(rabbit_misc, [pget/2, pget/3]).
-import(rabbit_test_util,[set_policy/5,
                          clear_policy/2,
                          default_options/0]).

-define(CLUSTER,
  fun(C) -> rabbit_test_configs:cluster(C, [lorenzo, kush, peter]) end).
-define(DEFAULT_VHOST_PATH, (<<"/">>)).
-define(POLICY, <<"^qm.location$">>).

-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

%% -------------------
%% Queue 'declarations'
%% -------------------
declare_args_with() -> ?CLUSTER.
declare_args(Cfgs) ->
    setup_test_environment(Cfgs),
    unset_location_config(Cfgs),
    QueueName = rabbit_misc:r(<<"/">>, queue, Q= <<"qm.test">>),
    Args      = [{<<"x-queue-master-locator">>, <<"min-masters">>}],
    Queue     = declare(Cfgs, QueueName, false, false, Args, none),
    verify_min_master(Cfgs, Q),
    delete_queue(Cfgs,Queue),
    stop_all(Cfgs),
    ok.

declare_policy_with() -> ?CLUSTER.
declare_policy(Cfgs) ->
    setup_test_environment(Cfgs),
    unset_location_config(Cfgs),
    set_location_policy(Cfgs, ?POLICY, <<"min-masters">>),
    QueueName = rabbit_misc:r(<<"/">>, queue, Q= <<"qm.test">>),
    Queue     = declare(Cfgs, QueueName, false, false, _Args=[], none),
    verify_min_master(Cfgs, Q),
    clear_location_policy(Cfgs, ?POLICY),
    delete_queue(Cfgs,Queue),
    stop_all(Cfgs),
    ok.

declare_config_with() -> ?CLUSTER.
declare_config(Cfgs) ->
    setup_test_environment(Cfgs),
    set_location_config(Cfgs, <<"min-masters">>),
    QueueName = rabbit_misc:r(<<"/">>, queue, Q= <<"qm.test">>),
    Queue     = declare(Cfgs, QueueName, false, false, _Args=[], none),
    verify_min_master(Cfgs, Q),
    delete_queue(Cfgs,Queue),
    unset_location_config(Cfgs),
    stop_all(Cfgs),
    ok.

%% -------------------
%% Test 'calculations'
%% -------------------
calculate_min_master_with() -> ?CLUSTER.
calculate_min_master(Cfgs) ->
    setup_test_environment(Cfgs),
    QueueName = rabbit_misc:r(<<"/">>, queue, Q= <<"qm.test">>),
    Args      = [{<<"x-queue-master-locator">>, <<"min-masters">>}],
    Queue     = declare(Cfgs, QueueName, false, false, Args, none),
    verify_min_master(Cfgs, Q),
    delete_queue(Cfgs,Queue),
    stop_all(Cfgs),
    ok.

calculate_random_with() -> ?CLUSTER.
calculate_random(Cfgs) ->
    setup_test_environment(Cfgs),
    QueueName = rabbit_misc:r(<<"/">>, queue, Q= <<"qm.test">>),
    Args      = [{<<"x-queue-master-locator">>, <<"random">>}],
    Queue     = declare(Cfgs, QueueName, false, false, Args, none),
    verify_random(Cfgs, Q),
    delete_queue(Cfgs,Queue),
    stop_all(Cfgs),
    ok.

calculate_client_local_with() -> ?CLUSTER.
calculate_client_local(Cfgs) ->
    setup_test_environment(Cfgs),
    QueueName = rabbit_misc:r(<<"/">>, queue, Q= <<"qm.test">>),
    Args      = [{<<"x-queue-master-locator">>, <<"client-local">>}],
    Queue     = declare(Cfgs, QueueName, false, false, Args, none),
    verify_client_local(Cfgs, Q),
    delete_queue(Cfgs,Queue),
    stop_all(Cfgs),
    ok.

%% -----------------
%% Setup environment
%% -----------------
setup_test_environment(Cfgs)  ->
    [distribute_queues(Cfg) || Cfg <- Cfgs],
    ok.

distribute_queues(Cfg0) ->
    ok  = rpc:call(pget(node, Cfg0), application, unset_env, [rabbit, queue_master_location]),
    Cfg = case rabbit_nodes:parts(pget(node, Cfg0)) of
              {"lorenzo",_} -> [{queue_count, 15}|Cfg0];
              {"kush",  _}  -> [{queue_count, 8} |Cfg0];
              {"peter",  _} -> [{queue_count, 1} |Cfg0]
          end,

    Channel = pget(channel, Cfg),
    ok = declare_queues(Channel, declare_fun(), pget(queue_count, Cfg)),
    ok = application:unset_env(rabbit, queue_master_location),
    {ok, Channel}.

%% -----------------------
%% Internal queue handling
%% -----------------------
declare_queues(Channel, DeclareFun, 1) -> DeclareFun(Channel);
declare_queues(Channel, DeclareFun, N) ->
    DeclareFun(Channel),
    declare_queues(Channel, DeclareFun, N-1).

declare_fun() ->
    fun(Channel) ->
            #'queue.declare_ok'{} = amqp_channel:call(Channel, get_random_queue_declare()),
            ok
    end.

get_random_queue_declare() ->
    #'queue.declare'{passive     = false,
                     durable     = false,
                     exclusive   = true,
                     auto_delete = false,
                     nowait      = false,
                     arguments   = []}.

%% -------------------------
%% Internal helper functions
%% -------------------------
get_cluster() -> [node()|nodes()].

min_master_node() -> rabbit_nodes:make("peter").

cluster_members(Nodes) -> [pget(node,Cfg) || Cfg <- Nodes].

set_location_config(Cfgs, Strategy) ->
    [ok = rpc:call(pget(node, Cfg), application, set_env,
                   [rabbit, queue_master_locator, Strategy]) || Cfg <- Cfgs],
    Cfgs.

unset_location_config(Cfgs) ->
    [ok = rpc:call(pget(node, Cfg), application, unset_env,
                   [rabbit, queue_master_locator]) || Cfg <- Cfgs],
    Cfgs.

declare([Cfg|_], QueueName, Durable, AutoDelete, Args, Owner) ->
    {new, Queue} = rpc:call(pget(node, Cfg), rabbit_amqqueue, declare,
                            [QueueName, Durable, AutoDelete, Args, Owner]),
    Queue.

verify_min_master([Cfg|_], Q) ->
    MinMaster = min_master_node(),
    {ok, MinMaster} =rpc:call(pget(node, Cfg), rabbit_queue_master_location_misc,
                              lookup_master, [Q,?DEFAULT_VHOST_PATH]).

verify_random([Cfg|_], Q) ->
    {ok, Node} = rpc:call(pget(node, Cfg), rabbit_queue_master_location_misc,
                          lookup_master, [Q,?DEFAULT_VHOST_PATH]),
    true = lists:member(Node, get_cluster()).

verify_client_local([Cfg|_], Q) ->
    Node = pget(node, Cfg),
    {ok, Node} = rpc:call(Node, rabbit_queue_master_location_misc,
                          lookup_master, [Q,?DEFAULT_VHOST_PATH]).

delete_queue([Cfg|_], Queue) ->
    {ok,_} = rpc:call(pget(node, Cfg), rabbit_amqqueue, delete, [Queue, true, true]).

stop_all(Cfgs) ->
    [rabbit_test_configs:stop_node(Cfg) || Cfg <- Cfgs].

set_location_policy([Cfg|_], Name, Strategy) ->
    ok = set_policy(Cfg, Name, <<".*">>, <<"queues">>,
                    [{<<"queue-master-locator">>, Strategy}]).

clear_location_policy([Cfg|_], Name) -> ok = clear_policy(Cfg, Name).
