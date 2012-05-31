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
-module(rabbit_ha_test_utils).

-compile(export_all).

wait(Node) ->
    NodeId  = systest_node:get_node_info(id, Node),
    Flags   = systest_node:get_node_info(flags, Node),
    ct:pal("Looking for pid file in ~p~n", [Flags]),
    LogFun  = fun ct:pal/2,
    case [V || {start, Start} <- Flags,
               {environment, "RABBITMQ_PID_FILE", V} <- Start] of
        [PF] -> rabbit_control_main:action(wait, NodeId, [PF], [], LogFun);
        []  -> throw(no_pidfile)
    end.

control_action(Command, Node) ->
    control_action(Command, Node, [], []).

control_action(Command, Node, Args) ->
    control_action(Command, Node, Args, []).

control_action(Command, Node, Args, Opts) ->
    rabbit_control_main:action(Command, Node, Args, Opts,
                               fun (Format, Args1) ->
                                       io:format(Format ++ " ...~n", Args1)
                               end).

cluster_status(Node) ->
    {lists:sort(rpc:call(Node, rabbit_mnesia, all_clustered_nodes, [])),
     lists:sort(rpc:call(Node, rabbit_mnesia, all_clustered_disc_nodes, [])),
     lists:sort(rpc:call(Node, rabbit_mnesia, running_clustered_nodes, []))}.
