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

suite() -> [{timetrap, {seconds, 60}}].

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
    [Rabbit, Hare, Bunny] = cluster_members(Config),
    assert_not_clustered(Rabbit),
    assert_not_clustered(Hare),
    assert_not_clustered(Bunny),

    stop_join_start(Rabbit, Bunny),
    assert_clustered([Rabbit, Bunny]),

    stop_join_start(Hare, Bunny, true),
    assert_cluster_status(
      {[Bunny, Hare, Rabbit], [Bunny, Rabbit], [Bunny, Hare, Rabbit]},
      [Rabbit, Hare, Bunny]),

    %% Allow clustering with already clustered node
    ok = stop_app(Rabbit),
    {ok, already_member} = join_cluster(Rabbit, Hare),
    ok = start_app(Rabbit),

    stop_reset_start(Rabbit),
    assert_not_clustered(Rabbit),
    assert_cluster_status({[Bunny, Hare], [Bunny], [Bunny, Hare]},
                          [Hare, Bunny]),

    stop_reset_start(Hare),
    assert_not_clustered(Hare),
    assert_not_clustered(Bunny).

join_cluster_bad_operations(Config) ->
    [Rabbit, Hare, Bunny] = cluster_members(Config),

    %% Non-existant node
    ok = stop_app(Rabbit),
    assert_failure(fun () -> join_cluster(Rabbit, non@existant) end),
    ok = start_app(Rabbit),
    assert_not_clustered(Rabbit),

    %% Trying to cluster with mnesia running
    assert_failure(fun () -> join_cluster(Rabbit, Bunny) end),
    assert_not_clustered(Rabbit),

    %% Trying to cluster the node with itself
    ok = stop_app(Rabbit),
    assert_failure(fun () -> join_cluster(Rabbit, Rabbit) end),
    ok = start_app(Rabbit),
    assert_not_clustered(Rabbit),

    %% Do not let the node leave the cluster or reset if it's the only
    %% ram node
    stop_join_start(Hare, Rabbit, true),
    assert_cluster_status({[Rabbit, Hare], [Rabbit], [Rabbit, Hare]},
                          [Rabbit, Hare]),
    ok = stop_app(Hare),
    assert_failure(fun () -> join_cluster(Rabbit, Bunny) end),
    assert_failure(fun () -> reset(Rabbit) end),
    ok = start_app(Hare),
    assert_cluster_status({[Rabbit, Hare], [Rabbit], [Rabbit, Hare]},
                          [Rabbit, Hare]).

%% This tests that the nodes in the cluster are notified immediately of a node
%% join, and not just after the app is started.
join_to_start_interval(Config) ->
    [Rabbit, Hare, _Bunny] = cluster_members(Config),

    ok = stop_app(Rabbit),
    ok = join_cluster(Rabbit, Hare),
    assert_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Hare]},
                          [Rabbit, Hare]),
    ok = start_app(Rabbit),
    assert_clustered([Rabbit, Hare]).

forget_cluster_node_test(Config) ->
    [Rabbit, Hare, Bunny] = cluster_members(Config),

    %% Trying to remove a node not in the cluster should fail
    assert_failure(fun () -> forget_cluster_node(Hare, Rabbit) end),

    stop_join_start(Rabbit, Hare),
    assert_clustered([Rabbit, Hare]),

    %% Trying to remove an online node should fail
    assert_failure(fun () -> forget_cluster_node(Hare, Rabbit) end),

    ok = stop_app(Rabbit),
    %% We're passing the --offline flag, but Hare is online
    assert_failure(fun () -> forget_cluster_node(Hare, Rabbit, true) end),
    %% Removing some non-existant node will fail
    assert_failure(fun () -> forget_cluster_node(Hare, non@existant) end),
    ok = forget_cluster_node(Hare, Rabbit),
    assert_not_clustered(Hare),
    assert_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Hare]},
                          [Rabbit]),

    %% Now we can't start Rabbit since it thinks that it's still in the cluster
    %% with Hare, while Hare disagrees.
    assert_failure(fun () -> start_app(Rabbit) end),

    ok = reset(Rabbit),
    ok = start_app(Rabbit),
    assert_not_clustered(Rabbit),

    %% Now we remove Rabbit from an offline node.
    stop_join_start(Bunny, Hare),
    stop_join_start(Rabbit, Hare),
    assert_clustered([Rabbit, Hare, Bunny]),
    ok = stop_app(Rabbit),
    ok = stop_app(Hare),
    ok = stop_app(Bunny),
    %% Rabbit was not the second-to-last to go down
    assert_failure(fun () -> forget_cluster_node(Rabbit, Bunny, true) end),
    %% This is fine but we need the flag
    assert_failure(fun () -> forget_cluster_node(Hare, Bunny) end),
    ok = forget_cluster_node(Hare, Bunny, true),
    ok = start_app(Hare),
    ok = start_app(Rabbit),
    %% Bunny still thinks its clustered with Rabbit and Hare
    assert_failure(fun () -> start_app(Bunny) end),
    ok = reset(Bunny),
    ok = start_app(Bunny),
    assert_not_clustered(Bunny),
    assert_clustered([Rabbit, Hare]).

forget_cluster_node_removes_things_test(Config) ->
    {_Cluster, [{{Rabbit, RabbitRef}, _},
                {{Hare,   HareRef},   _},
                {{_Bunny, _BunnyRef}, _}
               ]} = rabbit_ha_test_utils:cluster_members(Config),

    stop_join_start(Rabbit, Hare),
    {_RConn, RCh} = rabbit_ha_test_utils:connect(RabbitRef),
    #'queue.declare_ok'{} =
        amqp_channel:call(RCh, #'queue.declare'{queue   = <<"test">>,
                                                durable = true}),

    ok = stop_app(Rabbit),

    {_HConn, HCh} = rabbit_ha_test_utils:connect(HareRef),
    {'EXIT',{{shutdown,{server_initiated_close,404,_}}, _}} =
        (catch amqp_channel:call(HCh, #'queue.declare'{queue   = <<"test">>,
                                                       durable = true})),

    ok = forget_cluster_node(Hare, Rabbit),

    {_HConn2, HCh2} = rabbit_ha_test_utils:connect(HareRef),
    #'queue.declare_ok'{} =
        amqp_channel:call(HCh2, #'queue.declare'{queue   = <<"test">>,
                                                 durable = true}),
    ok.

change_cluster_node_type_test(Config) ->
    [Rabbit, Hare, _Bunny] = cluster_members(Config),

    %% Trying to change the ram node when not clustered should always fail
    ok = stop_app(Rabbit),
    assert_failure(fun () -> change_cluster_node_type(Rabbit, ram) end),
    assert_failure(fun () -> change_cluster_node_type(Rabbit, disc) end),
    ok = start_app(Rabbit),

    ok = stop_app(Rabbit),
    join_cluster(Rabbit, Hare),
    assert_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Hare]},
                          [Rabbit, Hare]),
    change_cluster_node_type(Rabbit, ram),
    assert_cluster_status({[Rabbit, Hare], [Hare], [Hare]},
                          [Rabbit, Hare]),
    change_cluster_node_type(Rabbit, disc),
    assert_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Hare]},
                          [Rabbit, Hare]),
    change_cluster_node_type(Rabbit, ram),
    ok = start_app(Rabbit),
    assert_cluster_status({[Rabbit, Hare], [Hare], [Hare, Rabbit]},
                          [Rabbit, Hare]),

    %% Changing to ram when you're the only ram node should fail
    ok = stop_app(Hare),
    assert_failure(fun () -> change_cluster_node_type(Hare, ram) end),
    ok = start_app(Hare).

change_cluster_when_node_offline(Config) ->
    [Rabbit, Hare, Bunny] = cluster_members(Config),

    %% Cluster the three notes
    stop_join_start(Rabbit, Hare),
    assert_clustered([Rabbit, Hare]),

    stop_join_start(Bunny, Hare),
    assert_clustered([Rabbit, Hare, Bunny]),

    %% Bring down Rabbit, and remove Bunny from the cluster while
    %% Rabbit is offline
    ok = stop_app(Rabbit),
    ok = stop_app(Bunny),
    ok = reset(Bunny),
    assert_cluster_status({[Bunny], [Bunny], []}, [Bunny]),
    assert_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Hare]}, [Hare]),
    assert_cluster_status(
      {[Rabbit, Hare, Bunny], [Rabbit, Hare, Bunny], [Hare, Bunny]}, [Rabbit]),

    %% Bring Rabbit back up
    ok = start_app(Rabbit),
    assert_clustered([Rabbit, Hare]),
    ok = start_app(Bunny),
    assert_not_clustered(Bunny),

    %% Now the same, but Rabbit is a RAM node, and we bring up Bunny
    %% before
    ok = stop_app(Rabbit),
    ok = change_cluster_node_type(Rabbit, ram),
    ok = start_app(Rabbit),
    stop_join_start(Bunny, Hare),
    assert_cluster_status(
      {[Rabbit, Hare, Bunny], [Hare, Bunny], [Rabbit, Hare, Bunny]},
      [Rabbit, Hare, Bunny]),
    ok = stop_app(Rabbit),
    ok = stop_app(Bunny),
    ok = reset(Bunny),
    ok = start_app(Bunny),
    assert_not_clustered(Bunny),
    assert_cluster_status({[Rabbit, Hare], [Hare], [Hare]}, [Hare]),
    assert_cluster_status(
      {[Rabbit, Hare, Bunny], [Hare, Bunny], [Hare, Bunny]},
      [Rabbit]),
    ok = start_app(Rabbit),
    assert_cluster_status({[Rabbit, Hare], [Hare], [Rabbit, Hare]},
                          [Rabbit, Hare]),
    assert_not_clustered(Bunny).

update_cluster_nodes_test(Config) ->
    [Rabbit, Hare, Bunny] = cluster_members(Config),

    %% Mnesia is running...
    assert_failure(fun () -> update_cluster_nodes(Rabbit, Hare) end),

    ok = stop_app(Rabbit),
    ok = join_cluster(Rabbit, Hare),
    ok = stop_app(Bunny),
    ok = join_cluster(Bunny, Hare),
    ok = start_app(Bunny),
    stop_reset_start(Hare),
    assert_failure(fun () -> start_app(Rabbit) end),
    %% Bogus node
    assert_failure(fun () -> update_cluster_nodes(Rabbit, non@existant) end),
    %% Inconsisent node
    assert_failure(fun () -> update_cluster_nodes(Rabbit, Hare) end),
    ok = update_cluster_nodes(Rabbit, Bunny),
    ok = start_app(Rabbit),
    assert_not_clustered(Hare),
    assert_clustered([Rabbit, Bunny]).

erlang_config_test(Config) ->
    [Rabbit, Hare, _Bunny] = cluster_members(Config),

    ok = stop_app(Hare),
    ok = reset(Hare),
    ok = rpc:call(Hare, application, set_env,
                  [rabbit, cluster_nodes, {[Rabbit], disc}]),
    ok = start_app(Hare),
    assert_clustered([Rabbit, Hare]),

    ok = stop_app(Hare),
    ok = reset(Hare),
    ok = rpc:call(Hare, application, set_env,
                  [rabbit, cluster_nodes, {[Rabbit], ram}]),
    ok = start_app(Hare),
    assert_cluster_status({[Rabbit, Hare], [Rabbit], [Rabbit, Hare]},
                          [Rabbit, Hare]),

    %% We get a warning but we start anyway
    ok = stop_app(Hare),
    ok = reset(Hare),
    ok = rpc:call(Hare, application, set_env,
                  [rabbit, cluster_nodes, {[non@existent], disc}]),
    ok = start_app(Hare),
    assert_not_clustered(Hare),
    assert_not_clustered(Rabbit),

    %% If we use a legacy config file, it still works (and a warning is emitted)
    ok = stop_app(Hare),
    ok = reset(Hare),
    ok = rpc:call(Hare, application, set_env,
                  [rabbit, cluster_nodes, [Rabbit]]),
    ok = start_app(Hare),
    assert_cluster_status({[Rabbit, Hare], [Rabbit], [Rabbit, Hare]},
                          [Rabbit, Hare]).

force_reset_test(Config) ->
    [Rabbit, Hare, _Bunny] = cluster_members(Config),

    stop_join_start(Rabbit, Hare),
    stop_app(Rabbit),
    force_reset(Rabbit),
    %% Hare thinks that Rabbit is still clustered
    assert_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Hare]},
                          [Hare]),
    %% %% ...but it isn't
    assert_cluster_status({[Rabbit], [Rabbit], []}, [Rabbit]),
    %% We can rejoin Rabbit and Hare
    update_cluster_nodes(Rabbit, Hare),
    start_app(Rabbit),
    assert_clustered([Rabbit, Hare]).

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
