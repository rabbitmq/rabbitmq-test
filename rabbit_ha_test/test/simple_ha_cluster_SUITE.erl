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

-include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

suite() -> [{timetrap, {seconds, 60}}].

all() ->
    [ {exports, Functions} | _ ] = ?MODULE:module_info(),
    [ FName || {FName, _} <- lists:filter(
                               fun ({module_info,_}) -> false;
                                   ({all,_}) -> false;
                                   ({init_per_suite,1}) -> false;
                                   ({end_per_suite,1}) -> false;
                                   ({_,1}) -> true;
                                   ({_,_}) -> false
                               end, Functions)].

init_per_suite(Config) ->
    systest:start_suite(?MODULE, Config).

end_per_suite(Config) ->
    systest:stop_suite(?MODULE, Config).

init_per_testcase(TestCase, Config) ->
    systest:start(TestCase, Config).

end_per_testcase(TestCase, Config) ->
    systest:stop(TestCase, Config).

we_can_start_rabbit_nodes(Config) ->
    Cluster = systest:active_cluster(Config),
    systest_cluster:print_status(Cluster),
    [begin
         Node = N#'systest.node_info'.id,
         ?assertEqual(pong, net_adm:ping(Node)),

         EbinPath = code:which(rabbit),
         ?assertMatch(EbinPath,
                      systest:interact(N, {code, which, [systest]})),

         OsPid = N#'systest.node_info'.os_pid,
         PidFile = filename:join(?config(priv_dir, Config),
                                 OsPid ++ ".pid"),
         ?assertEqual(true, filelib:is_regular(PidFile)),

         {ok, Pid} = file:read_file(PidFile),
         ?assertEqual(OsPid, binary_to_list(Pid))
     end || N <- Cluster#'systest.cluster'.nodes],
    ok.


