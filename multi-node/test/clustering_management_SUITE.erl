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
%% Copyright (c) 2007-2013 VMware, Inc.  All rights reserved.
%%
-module(clustering_management_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1,

         join_and_part_cluster/1, join_cluster_bad_operations/1,
         join_to_start_interval/1, forget_cluster_node_test/1,
         forget_cluster_node_removes_things_test/1,
         change_cluster_node_type_test/1, change_cluster_when_node_offline/1,
         update_cluster_nodes_test/1, erlang_config_test/1, force_reset_test/1
        ]).

-define(LOOP_RECURSION_DELAY, 100).

suite() -> [{timetrap, systest:settings("time_traps.cluster_management")}].

all() ->
    [join_and_part_cluster, join_cluster_bad_operations, join_to_start_interval,
     forget_cluster_node_test, change_cluster_node_type_test,
     change_cluster_when_node_offline, update_cluster_nodes_test,
     erlang_config_test, force_reset_test].

init_per_suite(Config) ->
    Config.
end_per_suite(_Config) ->
    ok.

join_and_part_cluster(Config) ->
    [Flopsy, Mopsy, Cottontail] = cluster_members(Config),
    assert_not_clustered(Flopsy),
    assert_not_clustered(Mopsy),
    assert_not_clustered(Cottontail),

    stop_join_start(Flopsy, Cottontail),
    assert_clustered([Flopsy, Cottontail]),

    stop_join_start(Mopsy, Cottontail, true),
    assert_cluster_status(
      {[Cottontail, Mopsy, Flopsy], [Cottontail, Flopsy], [Cottontail, Mopsy, Flopsy]},
      [Flopsy, Mopsy, Cottontail]),

    stop_reset_start(Flopsy),
    assert_not_clustered(Flopsy),
    assert_cluster_status({[Cottontail, Mopsy], [Cottontail], [Cottontail, Mopsy]},
                          [Mopsy, Cottontail]),

    stop_reset_start(Mopsy),
    assert_not_clustered(Mopsy),
    assert_not_clustered(Cottontail).

join_cluster_bad_operations(Config) ->
    [Flopsy, Mopsy, Cottontail] = cluster_members(Config),

    %% Non-existant node
    ok = stop_app(Flopsy),
    assert_failure(fun () -> join_cluster(Flopsy, non@existant) end),
    ok = start_app(Flopsy),
    assert_not_clustered(Flopsy),

    %% Trying to cluster with mnesia running
    assert_failure(fun () -> join_cluster(Flopsy, Cottontail) end),
    assert_not_clustered(Flopsy),

    %% Trying to cluster the node with itself
    ok = stop_app(Flopsy),
    assert_failure(fun () -> join_cluster(Flopsy, Flopsy) end),
    ok = start_app(Flopsy),
    assert_not_clustered(Flopsy),

    %% Fail if trying to cluster with already clustered node
    stop_join_start(Flopsy, Mopsy),
    assert_clustered([Flopsy, Mopsy]),
    ok = stop_app(Flopsy),
    assert_failure(fun () -> join_cluster(Flopsy, Mopsy) end),
    ok = start_app(Flopsy),
    assert_clustered([Flopsy, Mopsy]),

    %% Cleanup
    stop_reset_start(Flopsy),
    assert_not_clustered(Flopsy),
    assert_not_clustered(Mopsy),

    %% Do not let the node leave the cluster or reset if it's the only
    %% ram node
    stop_join_start(Mopsy, Flopsy, true),
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy], [Flopsy, Mopsy]},
                          [Flopsy, Mopsy]),
    ok = stop_app(Mopsy),
    assert_failure(fun () -> join_cluster(Flopsy, Cottontail) end),
    assert_failure(fun () -> reset(Flopsy) end),
    ok = start_app(Mopsy),
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy], [Flopsy, Mopsy]},
                          [Flopsy, Mopsy]).

%% This tests that the nodes in the cluster are notified immediately of a node
%% join, and not just after the app is started.
join_to_start_interval(Config) ->
    [Flopsy, Mopsy, _Cottontail] = cluster_members(Config),

    ok = stop_app(Flopsy),
    ok = join_cluster(Flopsy, Mopsy),
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy, Mopsy], [Mopsy]},
                          [Flopsy, Mopsy]),
    ok = start_app(Flopsy),
    assert_clustered([Flopsy, Mopsy]).

forget_cluster_node_test(Config) ->
    [Flopsy, Mopsy, Cottontail] = cluster_members(Config),

    %% Trying to remove a node not in the cluster should fail
    assert_failure(fun () -> forget_cluster_node(Mopsy, Flopsy) end),

    stop_join_start(Flopsy, Mopsy),
    assert_clustered([Flopsy, Mopsy]),

    %% Trying to remove an online node should fail
    assert_failure(fun () -> forget_cluster_node(Mopsy, Flopsy) end),

    ok = stop_app(Flopsy),
    %% We're passing the --offline flag, but Mopsy is online
    assert_failure(fun () -> forget_cluster_node(Mopsy, Flopsy, true) end),
    %% Removing some non-existant node will fail
    assert_failure(fun () -> forget_cluster_node(Mopsy, non@existant) end),
    ok = forget_cluster_node(Mopsy, Flopsy),
    assert_not_clustered(Mopsy),
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy, Mopsy], [Mopsy]},
                          [Flopsy]),

    %% Now we can't start Flopsy since it thinks that it's still in the cluster
    %% with Mopsy, while Mopsy disagrees.
    assert_failure(fun () -> start_app(Flopsy) end),

    ok = reset(Flopsy),
    ok = start_app(Flopsy),
    assert_not_clustered(Flopsy),

    %% Now we remove Flopsy from an offline node.
    stop_join_start(Cottontail, Mopsy),
    stop_join_start(Flopsy, Mopsy),
    assert_clustered([Flopsy, Mopsy, Cottontail]),
    ok = stop_app(Flopsy),
    ok = stop_app(Mopsy),
    ok = stop_app(Cottontail),
    %% Flopsy was not the second-to-last to go down
    assert_failure(fun () -> forget_cluster_node(Flopsy, Cottontail, true) end),
    %% This is fine but we need the flag
    assert_failure(fun () -> forget_cluster_node(Mopsy, Cottontail) end),
    ok = forget_cluster_node(Mopsy, Cottontail, true),
    ok = start_app(Mopsy),
    ok = start_app(Flopsy),
    %% Cottontail still thinks its clustered with Flopsy and Mopsy
    assert_failure(fun () -> start_app(Cottontail) end),
    ok = reset(Cottontail),
    ok = start_app(Cottontail),
    assert_not_clustered(Cottontail),
    assert_clustered([Flopsy, Mopsy]).

forget_cluster_node_removes_things_test(Config) ->
    {_Cluster, [{{Flopsy, FlopsyRef}, _},
                {{Mopsy,   MopsyRef},   _},
                {{_Cottontail, _CottontailRef}, _}
               ]} = rabbit_ha_test_utils:cluster_members(Config),

    stop_join_start(Flopsy, Mopsy),
    {_RConn, RCh} = rabbit_ha_test_utils:connect(FlopsyRef),
    #'queue.declare_ok'{} =
        amqp_channel:call(RCh, #'queue.declare'{queue   = <<"test">>,
                                                durable = true}),

    ok = stop_app(Flopsy),

    {_HConn, HCh} = rabbit_ha_test_utils:connect(MopsyRef),
    {'EXIT',{{shutdown,{server_initiated_close,404,_}}, _}} =
        (catch amqp_channel:call(HCh, #'queue.declare'{queue   = <<"test">>,
                                                       durable = true})),

    ok = forget_cluster_node(Mopsy, Flopsy),

    {_HConn2, HCh2} = rabbit_ha_test_utils:connect(MopsyRef),
    #'queue.declare_ok'{} =
        amqp_channel:call(HCh2, #'queue.declare'{queue   = <<"test">>,
                                                 durable = true}),
    ok.

change_cluster_node_type_test(Config) ->
    [Flopsy, Mopsy, _Cottontail] = cluster_members(Config),

    %% Trying to change the ram node when not clustered should always fail
    ok = stop_app(Flopsy),
    assert_failure(fun () -> change_cluster_node_type(Flopsy, ram) end),
    assert_failure(fun () -> change_cluster_node_type(Flopsy, disc) end),
    ok = start_app(Flopsy),

    ok = stop_app(Flopsy),
    join_cluster(Flopsy, Mopsy),
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy, Mopsy], [Mopsy]},
                          [Flopsy, Mopsy]),
    change_cluster_node_type(Flopsy, ram),
    assert_cluster_status({[Flopsy, Mopsy], [Mopsy], [Mopsy]},
                          [Flopsy, Mopsy]),
    change_cluster_node_type(Flopsy, disc),
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy, Mopsy], [Mopsy]},
                          [Flopsy, Mopsy]),
    change_cluster_node_type(Flopsy, ram),
    ok = start_app(Flopsy),
    assert_cluster_status({[Flopsy, Mopsy], [Mopsy], [Mopsy, Flopsy]},
                          [Flopsy, Mopsy]),

    %% Changing to ram when you're the only ram node should fail
    ok = stop_app(Mopsy),
    assert_failure(fun () -> change_cluster_node_type(Mopsy, ram) end),
    ok = start_app(Mopsy).

change_cluster_when_node_offline(Config) ->
    [Flopsy, Mopsy, Cottontail] = cluster_members(Config),

    %% Cluster the three notes
    stop_join_start(Flopsy, Mopsy),
    assert_clustered([Flopsy, Mopsy]),

    stop_join_start(Cottontail, Mopsy),
    assert_clustered([Flopsy, Mopsy, Cottontail]),

    %% Bring down Flopsy, and remove Cottontail from the cluster while
    %% Flopsy is offline
    ok = stop_app(Flopsy),
    ok = stop_app(Cottontail),
    ok = reset(Cottontail),
    assert_cluster_status({[Cottontail], [Cottontail], []}, [Cottontail]),
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy, Mopsy], [Mopsy]}, [Mopsy]),
    assert_cluster_status(
      {[Flopsy, Mopsy, Cottontail], [Flopsy, Mopsy, Cottontail], [Mopsy, Cottontail]}, [Flopsy]),

    %% Bring Flopsy back up
    ok = start_app(Flopsy),
    assert_clustered([Flopsy, Mopsy]),
    ok = start_app(Cottontail),
    assert_not_clustered(Cottontail),

    %% Now the same, but Flopsy is a RAM node, and we bring up Cottontail
    %% before
    ok = stop_app(Flopsy),
    ok = change_cluster_node_type(Flopsy, ram),
    ok = start_app(Flopsy),
    stop_join_start(Cottontail, Mopsy),
    assert_cluster_status(
      {[Flopsy, Mopsy, Cottontail], [Mopsy, Cottontail], [Flopsy, Mopsy, Cottontail]},
      [Flopsy, Mopsy, Cottontail]),
    ok = stop_app(Flopsy),
    ok = stop_app(Cottontail),
    ok = reset(Cottontail),
    ok = start_app(Cottontail),
    assert_not_clustered(Cottontail),
    assert_cluster_status({[Flopsy, Mopsy], [Mopsy], [Mopsy]}, [Mopsy]),
    assert_cluster_status(
      {[Flopsy, Mopsy, Cottontail], [Mopsy, Cottontail], [Mopsy, Cottontail]},
      [Flopsy]),
    ok = start_app(Flopsy),
    assert_cluster_status({[Flopsy, Mopsy], [Mopsy], [Flopsy, Mopsy]},
                          [Flopsy, Mopsy]),
    assert_not_clustered(Cottontail).

update_cluster_nodes_test(Config) ->
    [Flopsy, Mopsy, Cottontail] = cluster_members(Config),

    %% Mnesia is running...
    assert_failure(fun () -> update_cluster_nodes(Flopsy, Mopsy) end),

    ok = stop_app(Flopsy),
    ok = join_cluster(Flopsy, Mopsy),
    ok = stop_app(Cottontail),
    ok = join_cluster(Cottontail, Mopsy),
    ok = start_app(Cottontail),
    stop_reset_start(Mopsy),
    assert_failure(fun () -> start_app(Flopsy) end),
    %% Bogus node
    assert_failure(fun () -> update_cluster_nodes(Flopsy, non@existant) end),
    %% Inconsisent node
    assert_failure(fun () -> update_cluster_nodes(Flopsy, Mopsy) end),
    ok = update_cluster_nodes(Flopsy, Cottontail),
    ok = start_app(Flopsy),
    assert_not_clustered(Mopsy),
    assert_clustered([Flopsy, Cottontail]).

erlang_config_test(Config) ->
    [Flopsy, Mopsy, _Cottontail] = cluster_members(Config),

    ok = stop_app(Mopsy),
    ok = reset(Mopsy),
    ok = rpc:call(Mopsy, application, set_env,
                  [rabbit, cluster_nodes, {[Flopsy], disc}]),
    ok = start_app(Mopsy),
    assert_clustered([Flopsy, Mopsy]),

    ok = stop_app(Mopsy),
    ok = reset(Mopsy),
    ok = rpc:call(Mopsy, application, set_env,
                  [rabbit, cluster_nodes, {[Flopsy], ram}]),
    ok = start_app(Mopsy),
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy], [Flopsy, Mopsy]},
                          [Flopsy, Mopsy]),

    %% We get a warning but we start anyway
    ok = stop_app(Mopsy),
    ok = reset(Mopsy),
    ok = rpc:call(Mopsy, application, set_env,
                  [rabbit, cluster_nodes, {[non@existent], disc}]),
    ok = start_app(Mopsy),
    assert_not_clustered(Mopsy),
    assert_not_clustered(Flopsy),

    %% If we use a legacy config file, it still works (and a warning is emitted)
    ok = stop_app(Mopsy),
    ok = reset(Mopsy),
    ok = rpc:call(Mopsy, application, set_env,
                  [rabbit, cluster_nodes, [Flopsy]]),
    ok = start_app(Mopsy),
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy], [Flopsy, Mopsy]},
                          [Flopsy, Mopsy]).

force_reset_test(Config) ->
    [Flopsy, Mopsy, _Cottontail] = cluster_members(Config),

    stop_join_start(Flopsy, Mopsy),
    stop_app(Flopsy),
    force_reset(Flopsy),
    %% Mopsy thinks that Flopsy is still clustered
    assert_cluster_status({[Flopsy, Mopsy], [Flopsy, Mopsy], [Mopsy]},
                          [Mopsy]),
    %% %% ...but it isn't
    assert_cluster_status({[Flopsy], [Flopsy], []}, [Flopsy]),
    %% Mopsy still thinks Flopsy is in the cluster
    assert_failure(fun () -> join_cluster(Flopsy, Mopsy) end),
    %% We can rejoin Flopsy and Mopsy
    update_cluster_nodes(Flopsy, Mopsy),
    start_app(Flopsy),
    assert_clustered([Flopsy, Mopsy]).

%% ----------------------------------------------------------------------------
%% Internal utils

cluster_members(Config) ->
    Cluster = systest:active_sut(Config),
    [Id || {Id, _Ref} <- systest:list_processes(Cluster)].

assert_cluster_status(Status0, Nodes) ->
    Status = {AllNodes, _, _} = sort_cluster_status(Status0),
    wait_for_cluster_status(Status, AllNodes, Nodes).

wait_for_cluster_status(Status, AllNodes, Nodes) ->
    Max = systest:settings("limits.clustering_mgmt.status_check_max_wait")
        / ?LOOP_RECURSION_DELAY,
    wait_for_cluster_status(0, Max, Status, AllNodes, Nodes).

wait_for_cluster_status(N, Max, Status, _AllNodes, Nodes) when N >= Max ->
    error({cluster_status_max_tries_failed,
           [{nodes, Nodes},
            {expected_status, Status},
            {max_tried, Max}]});
wait_for_cluster_status(N, Max, Status, AllNodes, Nodes) ->
    case lists:all(fun (Node) ->
                            verify_status_equal(Node, Status, AllNodes)
                   end, Nodes) of
        true  -> ok;
        false -> timer:sleep(?LOOP_RECURSION_DELAY),
                 wait_for_cluster_status(N + 1, Max, Status, AllNodes, Nodes)
    end.

verify_status_equal(Node, Status, AllNodes) ->
    NodeStatus = sort_cluster_status(rabbit_ha_test_utils:cluster_status(Node)),
    (AllNodes =/= [Node]) =:= rpc:call(Node, rabbit_mnesia, is_clustered, [])
        andalso NodeStatus =:= Status.

sort_cluster_status({All, Disc, Running}) ->
    {lists:sort(All), lists:sort(Disc), lists:sort(Running)}.

assert_clustered(Nodes) ->
    assert_cluster_status({Nodes, Nodes, Nodes}, Nodes).

assert_not_clustered(Node) ->
    assert_cluster_status({[Node], [Node], [Node]}, [Node]).

assert_failure(Fun) ->
    case catch Fun() of
        {error, Reason}            -> Reason;
        {badrpc, {'EXIT', Reason}} -> Reason;
        Other                      -> exit({expected_failure, Other})
    end.

stop_app(Node) ->
    rabbit_ha_test_utils:control_action(stop_app, Node).

start_app(Node) ->
    rabbit_ha_test_utils:control_action(start_app, Node).

join_cluster(Node, To) ->
    join_cluster(Node, To, false).

join_cluster(Node, To, Ram) ->
    rabbit_ha_test_utils:control_action(
      join_cluster, Node, [atom_to_list(To)], [{"--ram", Ram}]).

reset(Node) ->
    rabbit_ha_test_utils:control_action(reset, Node).

force_reset(Node) ->
    rabbit_ha_test_utils:control_action(force_reset, Node).

forget_cluster_node(Node, Removee, RemoveWhenOffline) ->
    rabbit_ha_test_utils:control_action(
      forget_cluster_node, Node, [atom_to_list(Removee)],
      [{"--offline", RemoveWhenOffline}]).

forget_cluster_node(Node, Removee) ->
    forget_cluster_node(Node, Removee, false).

change_cluster_node_type(Node, Type) ->
    rabbit_ha_test_utils:control_action(change_cluster_node_type, Node,
                                        [atom_to_list(Type)]).

update_cluster_nodes(Node, DiscoveryNode) ->
    rabbit_ha_test_utils:control_action(update_cluster_nodes, Node,
                                        [atom_to_list(DiscoveryNode)]).

stop_join_start(Node, ClusterTo, Ram) ->
    ok = stop_app(Node),
    ok = join_cluster(Node, ClusterTo, Ram),
    ok = start_app(Node).

stop_join_start(Node, ClusterTo) ->
    stop_join_start(Node, ClusterTo, false).

stop_reset_start(Node) ->
    ok = stop_app(Node),
    ok = reset(Node),
    ok = start_app(Node).
