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

-include_lib("systest/include/systest.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

%%
%% systest_node on_start callbacks
%%

amqp_close(#'systest.node_info'{user=UserData}) ->
    Channel = ?CONFIG(amqp_channel, UserData, undefined),
    Connection = ?CONFIG(amqp_connection, UserData, undefined),
    close_channel(Channel),
    close_connection(Connection).

wait(Node) ->
    NodeId  = systest_node:get_node_info(id, Node),
    % Flags   = systest_node:get_node_info(private, Node),
    LogFun  = fun ct:pal/2,
    case node_eval("node.user.env", [{node, Node}]) of
        not_found -> throw(no_pidfile);
        Env -> case lists:keyfind("RABBITMQ_PID_FILE", 1, Env) of
                   false   -> throw(no_pidfile);
                   {_, PF} -> ct:pal("reading pid from ~s~n", [PF]),
                              rabbit_control_main:action(wait, NodeId,
                                                         [PF], [], LogFun)
               end
    end.

%%
%% Test Utility Functions
%%

await_response(Pid, Timeout) ->
    receive
        {Pid, Response} -> Response
    after
        Timeout ->
            {error, timeout}
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
    {rpc:call(Node, rabbit_mnesia, all_clustered_nodes, []),
     rpc:call(Node, rabbit_mnesia, all_clustered_disc_nodes, []),
     rpc:call(Node, rabbit_mnesia, running_clustered_nodes, [])}.


mirror_args([]) ->
    [{<<"x-ha-policy">>, longstr, <<"all">>}];
mirror_args(Nodes) ->
    [{<<"x-ha-policy">>, longstr, <<"nodes">>},
     {<<"x-ha-policy-params">>, array,
      [{longstr, list_to_binary(atom_to_list(N))} || N <- Nodes]}].

with_cluster(Config, TestFun) ->
    Cluster = systest:active_cluster(Config),
    systest_cluster:print_status(Cluster),
    Nodes = systest:cluster_nodes(Cluster),
    {ClusterTo, Members} = case [Id || {Id, _Ref} <- Nodes] of
                               [N | Ns] -> {N, Ns}
                           end,
    ct:pal("Clustering ~p~n", [[ClusterTo | Members]]),
    lists:foreach(fun (Node) -> cluster(Node, ClusterTo) end, Members),
    NodeConf = [begin
                    UserData = ?CONFIG(user, systest_node:node_data(Ref)),
                    amqp_open(Id, UserData)
                end || {Id, Ref} <- Nodes],
    TestFun(Cluster, NodeConf).

%%
%% Private API
%%

amqp_open(Id, UserData) ->
    NodePort = ?REQUIRE(amqp_port, UserData),
    {ok, Connection} =
        amqp_connection:start(#amqp_params_network{port=NodePort}),
    Channel = open_channel(Connection),
    {Id, {Connection, Channel}}.

cluster(Node, ClusterTo) ->
    ct:pal("clustering ~p with ~p~n", [Node, ClusterTo]),
    LogFn = fun ct:pal/2,
    rabbit_control_main:action(stop_app, Node, [], [], LogFn),
    rabbit_control_main:action(join_cluster, Node, [atom_to_list(ClusterTo)], [], LogFn),
    rabbit_control_main:action(start_app, Node, [], [], LogFn),
    ok = rpc:call(Node, rabbit, await_startup, []).

node_eval(Key, Node) ->
    systest_config:eval(Key, Node,
                        [{callback,
                            {node, fun systest_node:get_node_info/2}}]).

open_channel(Connection) ->
    {ok, Channel} = amqp_connection:open_channel(Connection),
    Channel.

close_connection(Connection) ->
    rabbit_misc:with_exit_handler(
      rabbit_misc:const(ok), fun () -> amqp_connection:close(Connection) end).

close_channel(Channel) ->
    rabbit_misc:with_exit_handler(
      rabbit_misc:const(ok), fun () -> amqp_channel:close(Channel) end).
