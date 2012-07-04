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
%% systest_node callbacks
%%

amqp_open(Id, UserData) ->
    NodePort = ?REQUIRE(amqp_port, UserData),
    Connection = open_connection(NodePort),
    Channel = open_channel(Connection),
    {Connection, Channel}.

open_connection(NodePort) ->
    {ok, Connection} =
        amqp_connection:start(#amqp_params_network{port=NodePort}),
    Connection.


%%
%% @doc A systest_node 'on_stop' callback that closes a connection and channel
%% which in the node's user data as <pre>amqp_connection</pre> and
%% <pre>amqp_channel</pre> respectively.
%%
amqp_close(Node) ->
    UserData = systest_node:get(user, Node),
    Channel = ?CONFIG(amqp_channel, UserData, undefined),
    Connection = ?CONFIG(amqp_connection, UserData, undefined),
    amqp_close(Channel, Connection).

amqp_close(Channel, Connection) ->
    close_channel(Channel),
    close_connection(Connection).

start_rabbit(Node) ->
    NodeId = systest_node:get(id, Node),
    LogFn = fun ct:log/2,
    rabbit_control_main:action(start_app, Node, [], [], LogFn),
    ok = rpc:call(Node, rabbit, await_startup, []).

%%
%% @doc runs <pre>rabbitmqctl wait</pre> against the supplied Node.
%% This is a systest_node 'on_start' callback, receiving a 'systest.node_info'
%% record, which holds the runtime environment (variables) in it's `user' field
%% (for details, see the systest_cli documentation).
%%
wait(Node) ->
    %% passing the records around like this really sucks - if only we had
    %% coroutines we could do this far more cleanly... :/
    NodeId  = systest_node:get(id, Node),
    LogFun  = fun ct:log/2,
    case node_eval("node.user.env", [{node, Node}]) of
        not_found -> throw(no_pidfile);
        Env -> case lists:keyfind("RABBITMQ_PID_FILE", 1, Env) of
                   false   -> throw(no_pidfile);
                   {_, PF} -> ct:log("reading pid from ~s~n", [PF]),
                              rabbit_control_main:action(wait, NodeId,
                                                         [PF], [], LogFun)
               end
    end.

%%
%% systest_cluster callbacks
%%

%%
%% @doc The systest_cluster on_start callback ensures that all our nodes are
%% properly clustered before we start testing. The return value of this
%% callback is ignored.
%%
make_cluster(Cluster) ->
    Members = systest_cluster:node_names(Cluster),
    ct:log("clustering ~p~n", [Members]),
    lists:foldl(fun cluster/2, [], Members).

%%
%% @doc This systest_cluster on_join callback sets up a single connection and
%% a single channel (on it), which is stored in the node's user-state for
%% use by our various test case functions. We wait until the cluster on_join
%% callback, because node on_start callbacks run *before* `make_cluster' could
%% potentially restart the rabbit application on each node, killing off our
%% connections and channels in the process.
%%
on_join(Node, _ClusterRef, _Siblings) ->
    Id = systest_node:get(id, Node),

    % ClusterMembers = cluster(Id, [atom_to_list(Id) || {Id, _} <- Siblings]),

    %% at this point we've already been clustered with all the other nodes,
    %% so we're good to go - now we can open up the connection+channel...
    UserData = systest_node:get(user, Node),
    {Connection, Channel} = amqp_open(Id, UserData),
    AmqpData = [{amqp_connection, Connection},
                {amqp_channel,    Channel}],
    %% we store these pids for later use....
    {store, AmqpData}.

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

mirror_args([]) ->
    [{<<"x-ha-policy">>, longstr, <<"all">>}];
mirror_args(Nodes) ->
    [{<<"x-ha-policy">>, longstr, <<"nodes">>},
     {<<"x-ha-policy-params">>, array,
      [{longstr, list_to_binary(atom_to_list(N))} || N <- Nodes]}].

cluster_members(Config) ->
    Cluster = systest:active_cluster(Config),
    {Cluster, [{{Id, Ref}, amqp_config(Ref)} ||
                            {Id, Ref} <- systest:cluster_nodes(Cluster)]}.

amqp_config(NodeRef) ->
    UserData = systest_node:user_data(NodeRef),
    {?REQUIRE(amqp_connection, UserData), ?REQUIRE(amqp_channel, UserData)}.

with_cluster(Config, TestFun) ->
    Cluster = systest:active_cluster(Config),
    systest_cluster:print_status(Cluster),
    Nodes = systest:cluster_nodes(Cluster),
    Members = [Id || {Id, Ref} <- Nodes],
    ct:log("clustering ~p~n", [Members]),
    lists:foldl(fun cluster/2, [], Members),
    NodeConf = [begin
                    UserData = systest_node:user_data(Ref),
                    AmqpProcs = amqp_open(Id, UserData),
                    {Connection, Channel} = AmqpProcs,
                    AmqpData = [{amqp_connection, Connection},
                                {amqp_channel,    Channel}|UserData],
                    ok = systest_node:user_data(Ref, AmqpData),
                    {{Id, Ref}, AmqpProcs}
                end || {Id, Ref} <- Nodes],
    TestFun(Cluster, NodeConf).

cluster_with(Node, Nodes) ->
    lists:foldl(fun cluster/2, [], [Node|Nodes]).

%%
%% Private API
%%

cluster(Node, []) ->
    [atom_to_list(Node)];
cluster(Node, Acc) ->
    NodeS = atom_to_list(Node),
    NewAcc = [NodeS|Acc],
    ct:log("clustering ~p with ~p~n", [Node, Acc]),
    LogFn = fun ct:log/2,
    rabbit_control_main:action(stop_app, Node, [], [], LogFn),
    rabbit_control_main:action(reset, Node, [], [], LogFn),
    rabbit_control_main:action(cluster, Node, NewAcc, [], LogFn),
    rabbit_control_main:action(start_app, Node, [], [], LogFn),
    ok = rpc:call(Node, rabbit, await_startup, []),
    NewAcc.

node_eval(Key, Node) ->
    systest_config:eval(Key, Node,
                        [{callback,
                            {node, fun systest_node:get/2}}]).

open_channel(Connection) ->
    {ok, Channel} = amqp_connection:open_channel(Connection),
    Channel.

close_connection(Connection) ->
    ct:log("closing connection ~p~n", [Connection]),
    rabbit_misc:with_exit_handler(
      rabbit_misc:const(ok), fun () -> amqp_connection:close(Connection) end).

close_channel(Channel) ->
    ct:log("closing channel ~p~n", [Channel]),
    rabbit_misc:with_exit_handler(
      rabbit_misc:const(ok), fun () -> amqp_channel:close(Channel) end).
