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

         join_and_part_cluster/1
        ]).

suite() -> [{timetrap, {seconds, 60}}].

all() ->
    [join_and_part_cluster].

init_per_suite(Config) ->
    Config.
end_per_suite(_Config) ->
    ok.

join_and_part_cluster(Config) ->
    [Rabbit, Hare, Bunny] = cluster_nodes(Config),

    rabbit_ha_test_utils:control_action(stop_app, Rabbit),
    rabbit_ha_test_utils:control_action(join_cluster, Rabbit,
                                        [atom_to_list(Bunny)]),
    rabbit_ha_test_utils:control_action(start_app, Rabbit),

    check_cluster_status(
      {[Bunny, Rabbit], [Bunny, Rabbit], [Bunny, Rabbit]},
      [Rabbit, Bunny]),

    rabbit_ha_test_utils:control_action(stop_app, Hare),
    rabbit_ha_test_utils:control_action(
      join_cluster, Hare, [atom_to_list(Bunny)], [{"--ram", true}]),
    rabbit_ha_test_utils:control_action(start_app, Hare),

    check_cluster_status(
      {[Bunny, Hare, Rabbit], [Bunny, Rabbit], [Bunny, Hare, Rabbit]},
      [Rabbit, Hare, Bunny]),

    rabbit_ha_test_utils:control_action(stop_app, Rabbit),
    rabbit_ha_test_utils:control_action(reset, Rabbit),
    rabbit_ha_test_utils:control_action(start_app, Rabbit),

    check_cluster_status({[Rabbit], [Rabbit], [Rabbit]}, [Rabbit]),
    check_cluster_status({[Bunny, Hare], [Bunny], [Bunny, Hare]},
                         [Hare, Bunny]),

    rabbit_ha_test_utils:control_action(stop_app, Hare),
    rabbit_ha_test_utils:control_action(reset, Hare),
    rabbit_ha_test_utils:control_action(start_app, Hare),

    check_not_clustered(Hare),
    check_not_clustered(Bunny).

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
