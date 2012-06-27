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
-module(clustering_management_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1,

         join_and_part_cluster/1, join_cluster_bad_operations/1,
         join_to_start_interval/1, remove_offline_node/1,
         remove_node_and_recluster/1
        ]).

suite() -> [{timetrap, {seconds, 60}}].

all() ->
    [join_and_part_cluster, join_cluster_bad_operations,
     join_to_start_interval, remove_offline_node,
     remove_node_and_recluster].

init_per_suite(Config) ->
    Config.
end_per_suite(_Config) ->
    ok.

join_and_part_cluster(Config) ->
    [Rabbit, Hare, Bunny] = cluster_nodes(Config),

    stop_app(Rabbit),
    join_cluster(Rabbit, Bunny),
    start_app(Rabbit),

    check_cluster_status(
      {[Bunny, Rabbit], [Bunny, Rabbit], [Bunny, Rabbit]},
      [Rabbit, Bunny]),

    stop_app(Hare),
    join_cluster(Hare, Bunny, true),
    start_app(Hare),

    check_cluster_status(
      {[Bunny, Hare, Rabbit], [Bunny, Rabbit], [Bunny, Hare, Rabbit]},
      [Rabbit, Hare, Bunny]),

    stop_app(Rabbit),
    reset(Rabbit),
    start_app(Rabbit),

    check_cluster_status({[Rabbit], [Rabbit], [Rabbit]}, [Rabbit]),
    check_cluster_status({[Bunny, Hare], [Bunny], [Bunny, Hare]},
                         [Hare, Bunny]),

    stop_app(Hare),
    reset(Hare),
    start_app(Hare),

    check_not_clustered(Hare),
    check_not_clustered(Bunny).

join_cluster_bad_operations(Config) ->
    [Rabbit, Hare, Bunny] = cluster_nodes(Config),

    %% Non-existant node
    stop_app(Rabbit),
    check_failure(fun () -> join_cluster(Rabbit, non@existant) end),
    start_app(Rabbit),
    check_not_clustered(Rabbit),

    %% Trying to cluster with mnesia running
    check_failure(fun () -> join_cluster(Rabbit, Bunny) end),
    check_not_clustered(Rabbit),

    %% Trying to cluster the node with itself
    stop_app(Rabbit),
    check_failure(fun () -> join_cluster(Rabbit, Rabbit) end),
    start_app(Rabbit),
    check_not_clustered(Rabbit),

    %% Fail if trying to cluster with already clustered node
    stop_app(Rabbit),
    join_cluster(Rabbit, Hare),
    start_app(Rabbit),
    check_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Rabbit, Hare]},
                         [Rabbit, Hare]),
    stop_app(Rabbit),
    check_failure(fun () -> join_cluster(Rabbit, Hare) end),
    start_app(Rabbit),
    check_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Rabbit, Hare]},
                         [Rabbit, Hare]),

    %% Cleanup
    stop_app(Rabbit),
    reset(Rabbit),
    start_app(Rabbit),
    check_not_clustered(Rabbit),
    check_not_clustered(Hare),

    %% Do not let the node leave the cluster or reset if it's the only
    %% ram node
    stop_app(Hare),
    join_cluster(Hare, Rabbit, true),
    start_app(Hare),
    check_cluster_status({[Rabbit, Hare], [Rabbit], [Rabbit, Hare]},
                         [Rabbit, Hare]),
    stop_app(Hare),
    check_failure(fun () -> join_cluster(Rabbit, Bunny) end),
    check_failure(fun () -> reset(Rabbit) end),
    start_app(Hare),
    check_cluster_status({[Rabbit, Hare], [Rabbit], [Rabbit, Hare]},
                         [Rabbit, Hare]).

%% This tests that the nodes in the cluster are notified immediately of a node
%% join, and not just after the app is started.
join_to_start_interval(Config) ->
    [Rabbit, Hare, _Bunny] = cluster_nodes(Config),
    check_not_clustered(Rabbit),
    check_not_clustered(Hare),

    stop_app(Rabbit),
    join_cluster(Rabbit, Hare),
    check_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Hare]},
                         [Rabbit, Hare]),
    start_app(Rabbit),
    check_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Rabbit, Hare]},
                         [Rabbit, Hare]).

remove_offline_node(Config) ->
    [Rabbit, Hare, _Bunny] = cluster_nodes(Config),
    check_not_clustered(Rabbit),
    check_not_clustered(Hare),

    %% Trying to remove a node not in the cluster should fail
    check_failure(fun () -> remove_node(Hare, Rabbit) end),

    stop_app(Rabbit),
    join_cluster(Rabbit, Hare),
    check_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Hare]},
                         [Rabbit, Hare]),
    start_app(Rabbit),

    %% Trying to remove an online node should fail
    check_failure(fun () -> remove_node(Hare, Rabbit) end),

    stop_app(Rabbit),
    remove_node(Hare, Rabbit),
    check_not_clustered(Hare),

    %% Now we can't start Rabbit since it thinks that it's still in the cluster
    %% with Hare, while Hare disagrees.
    check_failure(fun () -> start_app(Rabbit) end).

remove_node_and_recluster(Config) ->
    [Rabbit, Hare, Bunny] = cluster_nodes(Config),
    check_not_clustered(Rabbit),
    check_not_clustered(Hare),

    stop_app(Rabbit),
    join_cluster(Rabbit, Hare),
    start_app(Rabbit),
    check_cluster_status({[Rabbit, Hare], [Rabbit, Hare], [Rabbit, Hare]},
                         [Rabbit, Hare]),

    stop_app(Rabbit),
    remove_node(Hare, Rabbit),
    check_not_clustered(Hare),

    stop_app(Bunny),
    join_cluster(Bunny, Hare),
    start_app(Bunny),
    check_cluster_status({[Bunny, Hare], [Bunny, Hare], [Bunny, Hare]},
                         [Bunny, Hare]),

    stop_app(Hare),
    reset(Hare),
    check_not_clustered(Hare),
    check_not_clustered(Bunny),

    recluster(Rabbit, Bunny),
    start_app(Rabbit),
    check_cluster_status({[Rabbit, Bunny], [Rabbit, Bunny], [Rabbit, Bunny]},
                         [Rabbit, Bunny]).

%% ----------------------------------------------------------------------------
%% Internal utils

cluster_nodes(Config) ->
    Cluster = systest:active_cluster(Config),
    systest_cluster:print_status(Cluster),
    [N || {N, _} <- systest:cluster_nodes(Cluster)].

check_cluster_status(Status0, Nodes) ->
    SortStatus =
        fun ({All, Disc, Running}) ->
                {lists:sort(All), lists:sort(Disc), lists:sort(Running)}
        end,
    Status = {AllNodes, _, _} = SortStatus(Status0),
    lists:foreach(
      fun (Node) ->
              ?assertEqual(AllNodes =/= [Node],
                           rpc:call(Node, rabbit_mnesia, is_clustered, [])),
              ?assertEqual(
                 Status, SortStatus(rabbit_ha_test_utils:cluster_status(Node)))
      end, Nodes).

check_not_clustered(Node) ->
    check_cluster_status({[Node], [Node], [Node]}, [Node]).

check_failure(Fun) ->
    case catch Fun() of
        {error, Reason} -> Reason
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

remove_node(Node, Removee) ->
    rabbit_ha_test_utils:control_action(remove_node, Node,
                                        [atom_to_list(Removee)]).

recluster(Node, DiscoveryNode) ->
    rabbit_ha_test_utils:control_action(remove_node, Node,
                                        [atom_to_list(DiscoveryNode)]).
