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
-include_lib("eunit/include/eunit.hrl").
-include_lib("systest/include/systest.hrl").

%% include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

suite() -> [{timetrap, {seconds, 60}}].

all() ->
    systest_suite:export_all(?MODULE).

init_per_testcase(TestCase, Config) ->
    systest:start(TestCase, Config).
    % ConnectedNodes = [rabbit_ha_test_utils:amqp_open(N) || N <- Nodes],

end_per_testcase(TestCase, Config) ->
    systest:stop(TestCase, Config).

starting_rabbit_nodes(Config) ->
    Cluster = systest:active_cluster(Config),
    systest_cluster:print_status(Cluster),
    % Cluster = starting_rabbit_nodes,
    % ct:pal("~p~n", [systest_cluster:check_config(Cluster, Config)]),
    ok.

starting_connected_nodes(Config) ->
    Cluster = systest:active_cluster(Config),
    systest_cluster:print_status(Cluster),
    ok.

