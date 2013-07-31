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
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2013 GoPivotal, Inc.  All rights reserved.
%%
-module(rabbit_ha_test_utils).

-include_lib("systest/include/systest.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

%%
%% systest_proc callbacks
%%

%%
%% @doc A systest_node 'on_stop' callback that closes a connection and channel
%% which in the node's user data as <pre>amqp_connection</pre> and
%% <pre>amqp_channel</pre> respectively. We also stop rabbit, so that the
%% cover-stop hooks do not break the behaviour of the remote nodes in the
%% many (and spectacular) ways we've seen in the past (e.g., bug25070).
%% @end
disconnect_from_node(Node) ->
    UserData = systest:process_data(user, Node),
    Channel = ?CONFIG(amqp_channel, UserData, undefined),
    Connection = ?CONFIG(amqp_connection, UserData, undefined),
    amqp_close(Channel, Connection).

%%
%% @doc A systest 'on_start' callback that starts up the rabbit application
%% on the target node. We do this *after* the node is up an running to ensure
%% that code coverage is already started prior to doing any actual work
%% @end
start_rabbit(Node) ->
    NodeId = systest:process_data(id, Node),
    systest:log("starting rabbit application on ~p~n", [NodeId]),
    control_action(start_app, NodeId),
    wait(Node).

%%
%% @doc A systest 'on_stop' callback that stops the rabbit application
%% on the target node. SysTest runs these hooks *before* code coverage is
%% stopped on the node, which prevents the behaviour we saw in bug25070.
stop_rabbit(Node) ->
    NodeId = systest:process_data(id, Node),
    control_action(stop_app, NodeId).

%%
%% @doc runs <pre>rabbitmqctl wait</pre> against the supplied Node.
%% This is a systest_node 'on_start' callback, receiving a 'systest.node_info'
%% record, which holds the runtime environment (variables) in it's `user' field
%% (for details, see the systest_cli documentation).
%%
wait(Node) ->
    %% passing the records around like this really sucks - if only we had
    %% coroutines we could do this far more cleanly... :/
    NodeId  = systest:process_data(id, Node),
    UserData = systest:process_data(user, Node),
    case proplists:get_value(env, UserData, not_found) of
        not_found -> throw(no_pidfile);
        Env -> case lists:keyfind("RABBITMQ_PID_FILE", 1, Env) of
                   false   -> throw(no_pidfile);
                   {_, PF} -> systest:log("reading pid from ~s~n", [PF]),
                              control_action(wait, NodeId, [PF])
               end
    end.

%%
%% systest_sut callbacks
%%

%%
%% @doc The systest_sut on_start callback ensures that all our nodes are
%% properly clustered before we start testing. The return value of this
%% callback is ignored.
%%
make_cluster(SUT) ->
    Members = live_members(SUT),
    systest:log("clustering ~p~n", [Members]),
    case Members of
        [To | Rest] -> lists:foreach(fun (Node) -> cluster(Node, To) end, Rest);
        _           -> ok
    end.

live_members(SUT) ->
    [Id || {Id, Ref} <- systest:list_processes(SUT),
           systest:process_activity_state(Ref) =/= not_started].

declare_ha_policies(SUT) ->
    Members = [Node | _] = live_members(SUT),
    set_policy(Node, <<"^ha.all.">>, <<"all">>),
    set_policy(Node, <<"^ha.nodes.">>, <<"nodes">>, [a2b(M) || M <- Members]),
    TwoNodes = [a2b(M) || M <- lists:sublist(Members, 2)],
    set_policy(Node, <<"^ha.two.">>, <<"nodes">>, TwoNodes),
    set_policy(Node, <<"^ha.auto.">>, <<"nodes">>, TwoNodes, <<"automatic">>).

%%
%% @doc This systest_sut on_join callback sets up a single connection and
%% a single channel (on it), which is stored in the node's user-state for
%% use by our various test case functions. We wait until the SUT on_join
%% callback, because proc on_start callbacks run *before* `make_cluster' could
%% potentially restart the rabbit application on each node, killing off our
%% connections and channels in the process.
%%
connect_to_node(Node, _ClusterRef, _Siblings) ->
    Id = systest:process_data(id, Node),
    %% at this point we've already been clustered with all the other nodes,
    %% so we're good to go - now we can open up the connection+channel...
    UserData = systest:process_data(user, Node),
    systest:log("opening AMQP connection + channel for ~p~n", [Id]),
    {Connection, Channel} = amqp_open(Id, UserData),
    AmqpData = [{amqp_connection, Connection},
                {amqp_channel,    Channel}],
    %% we store these pids for later use....
    {store, AmqpData}.

connect(NodeRef) ->
    UserData = systest:read_process_user_data(NodeRef),
    NodePort = ?REQUIRE(amqp_port, UserData),
    {ok, Conn} = amqp_connection:start(#amqp_params_network{port = NodePort}),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    {Conn, Ch}.

%%
%% Test Utility Functions
%%

amqp_port(NodeRef) ->
    UserData = systest:read_process_user_data(NodeRef),
    Port = ?REQUIRE(amqp_port, UserData),
    Port.

await_response(Pid, Timeout) ->
    receive
        {Pid, Response} -> Response
    after
        Timeout ->
            {error, timeout}
    end.

read_timeout(SettingsKey) ->
    case systest:settings(SettingsKey) of
        {minutes, M} -> M * 60000;
        {seconds, S} -> S * 1000;
        Other        -> throw({illegal_timetrap, Other})
    end.

set_policy(Node, Pattern, HAMode) ->
    set_policy0(Node, Pattern, [{<<"ha-mode">>,   HAMode}]).

set_policy(Node, Pattern, HAMode, HAParams) ->
    set_policy0(Node, Pattern, [{<<"ha-mode">>,   HAMode},
                                {<<"ha-params">>, HAParams}]).

set_policy(Node, Pattern, HAMode, HAParams, HASyncMode) ->
    set_policy0(Node, Pattern, [{<<"ha-mode">>,      HAMode},
                                {<<"ha-params">>,    HAParams},
                                {<<"ha-sync-mode">>, HASyncMode}]).

set_policy0(Node, Pattern, Definition) ->
    ok = rpc:call(Node, rabbit_policy, set,
                  [<<"/">>, Pattern, Pattern, Definition, undefined]).

clear_policy(Node, Pattern) ->
    ok = rpc:call(Node, rabbit_policy, delete, [<<"/">>, Pattern]).

control_action(Command, Node) ->
    control_action(Command, Node, [], []).

control_action(Command, Node, Args) ->
    control_action(Command, Node, Args, []).

control_action(Command, Node, Args, Opts) ->
    rabbit_control_main:action(Command, Node, Args, Opts,
                               fun (Fmt, FmtArgs) ->
                                       systest:log(Fmt ++ "~n", FmtArgs)
                               end).

cluster_status(Node) ->
    {rpc:call(Node, rabbit_mnesia, cluster_nodes, [all]),
     rpc:call(Node, rabbit_mnesia, cluster_nodes, [disc]),
     rpc:call(Node, rabbit_mnesia, cluster_nodes, [running])}.


cluster_members(Config) ->
    Cluster = systest:active_sut(Config),
    {Cluster, [{{Id, Ref}, amqp_config(Ref)} ||
                  {Id, Ref} <- systest:list_processes(Cluster)]}.

amqp_config(NodeRef) ->
    UserData = systest:read_process_user_data(NodeRef),
    {?REQUIRE(amqp_connection, UserData), ?REQUIRE(amqp_channel, UserData)}.

cluster(Node, ClusterTo) ->
    systest:log("clustering ~p with ~p~n", [Node, ClusterTo]),
    control_action(stop_app, Node),
    control_action(join_cluster, Node, [atom_to_list(ClusterTo)]),
    control_action(start_app, Node),
    ok = rpc:call(Node, rabbit, await_startup, []).

amqp_open(_Id, UserData) ->
    NodePort = ?REQUIRE(amqp_port, UserData),
    Connection = open_connection(NodePort),
    Channel = open_channel(Connection),
    {Connection, Channel}.

open_connection(NodePort) ->
    {ok, Connection} =
        amqp_connection:start(#amqp_params_network{port=NodePort}),
    Connection.

stop_app(Node) -> control_action(stop_app, Node).

start_app(Node) -> control_action(start_app, Node).

%%
%% Private API
%%

amqp_close(Channel, Connection) ->
    close_channel(Channel),
    close_connection(Connection).


node_eval(Key, Node) ->
    systest_config:eval(Key, Node,
                        [{callback,
                            {proc, fun systest_proc:get/2}}]).

open_channel(Connection) ->
    {ok, Channel} = amqp_connection:open_channel(Connection),
    Channel.

close_connection(Connection) ->
    systest:log("closing connection ~p~n", [Connection]),
    rabbit_misc:with_exit_handler(
      rabbit_misc:const(ok), fun () -> amqp_connection:close(Connection) end).

close_channel(Channel) ->
    systest:log("closing channel ~p~n", [Channel]),
    rabbit_misc:with_exit_handler(
      rabbit_misc:const(ok), fun () -> amqp_channel:close(Channel) end).

a2b(A) -> list_to_binary(atom_to_list(A)).
