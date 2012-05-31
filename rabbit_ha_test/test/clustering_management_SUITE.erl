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

-compile(export_all).

suite() -> [{timetrap, {seconds, 60}}].

all() ->
    systest_suite:export_all(?MODULE).

init_per_testcase(_TestCase, Config) ->
    systest:start(clustering_management, Config).

end_per_testcase(_TestCase, Config) ->
    systest:stop(clustering_management, Config).

simple_cluster(Config) ->
    Rabbit = rabbit_nodes:make("rabbit"),
    Hare = rabbit_nodes:make("hare"),
    Bunny = rabbit_nodes:make("bunny"),

    rabbit_ha_test_utils:control_action(stop_app, Rabbit),
    rabbit_ha_test_utils:control_action(join_cluster, Rabbit,
                                        [atom_to_list(Bunny)]),
    rabbit_ha_test_utils:control_action(start_app, Rabbit),

    ?assertEqual(true, rpc:call(Rabbit, rabbit_mnesia, is_clustered, [])),
    ?assertEqual(true, rpc:call(Bunny, rabbit_mnesia, is_clustered, [])),
    ?assertEqual({[Bunny, Rabbit], [Bunny, Rabbit], [Bunny, Rabbit]},
                 rabbit_ha_test_utils:cluster_status(Rabbit)),
    ?assertEqual({[Bunny, Rabbit], [Bunny, Rabbit], [Bunny, Rabbit]},
                 rabbit_ha_test_utils:cluster_status(Bunny)),

    rabbit_ha_test_utils:control_action(stop_app, Hare),
    rabbit_ha_test_utils:control_action(
      join_cluster, Hare, [atom_to_list(Bunny)], [{"--ram", true}]),
    rabbit_ha_test_utils:control_action(start_app, Hare),

    ?assertEqual(true, rpc:call(Hare, rabbit_mnesia, is_clustered, [])),

    ?assertEqual(
       {[Bunny, Hare, Rabbit], [Bunny, Rabbit], [Bunny, Hare, Rabbit]},
       rabbit_ha_test_utils:cluster_status(Rabbit)),
    ?assertEqual(
       {[Bunny, Hare, Rabbit], [Bunny, Rabbit], [Bunny, Hare, Rabbit]},
       rabbit_ha_test_utils:cluster_status(Hare)),
    ?assertEqual(
       {[Bunny, Hare, Rabbit], [Bunny, Rabbit], [Bunny, Hare, Rabbit]},
       rabbit_ha_test_utils:cluster_status(Bunny)),

    rabbit_ha_test_utils:control_action(stop_app, Rabbit),
    rabbit_ha_test_utils:control_action(reset, Rabbit),
    rabbit_ha_test_utils:control_action(start_app, Rabbit),

    rabbit_ha_test_utils:control_action(stop_app, Hare),
    rabbit_ha_test_utils:control_action(reset, Hare),
    rabbit_ha_test_utils:control_action(start_app, Hare),

    rabbit_ha_test_utils:control_action(stop_app, Bunny),
    rabbit_ha_test_utils:control_action(reset, Bunny),
    rabbit_ha_test_utils:control_action(start_app, Bunny).
