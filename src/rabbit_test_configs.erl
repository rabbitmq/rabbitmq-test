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
%% Copyright (c) 2007-2014 GoPivotal, Inc.  All rights reserved.
%%
-module(rabbit_test_configs).

-include_lib("amqp_client/include/amqp_client.hrl").

-export([cluster/1, cluster_ab/0, cluster_abc/0, start_abc/0]).
-export([start_nodes/2, add_to_cluster/2]).
-export([stop_nodes/1, stop_node/1, kill_node/1, basedir/0]).

-import(rabbit_test_utils, [set_policy/3, set_policy/4, set_policy/5, a2b/1]).
-import(rabbit_misc, [pget/2]).

cluster_ab()  -> cluster([a, b]).
cluster_abc() -> cluster([a, b, c]).
start_abc()   -> start_nodes([a, b, c]).

cluster(NodeNames) ->
    start_connections(
      set_default_policies(build_cluster(start_nodes(NodeNames)))).

start_nodes(NodeNames) ->
    recursive_delete(basedir() ++ "/nodes"),
    start_nodes(NodeNames, 5672).

start_nodes(NodeNames, FirstPort) ->
    {ok, Already0} = net_adm:names(),
    Already = [list_to_atom(N) || {N, _P} <- Already0],
    [check_node_not_running(Node, Already) || Node <- NodeNames],
    Ports = lists:seq(FirstPort, length(NodeNames) + FirstPort - 1),
    Nodes = [[{nodename, N}, {port, P}]
             || {N, P} <- lists:zip(NodeNames, Ports)],
    Base = basedir() ++ "/nodes",
    [start_node(Node, Base) || Node <- Nodes].

check_node_not_running(Node, Already) ->
    case lists:member(Node, Already) of
        true  -> exit({node_already_running, Node});
        false -> ok
    end.

start_node(Cfg, Base) ->
    Nodename = pget(nodename, Cfg),
    Port = pget(port, Cfg),
    PidFile = rabbit_misc:format("~s/~s.pid", [Base, Nodename]),
    Linked =
        execute_bg(
          [{"RABBITMQ_MNESIA_BASE", {"~s/rabbitmq-~s-mnesia", [Base,Nodename]}},
           {"RABBITMQ_LOG_BASE",    {"~s", [Base]}},
           {"RABBITMQ_NODENAME",    {"~s", [Nodename]}},
           {"RABBITMQ_NODE_PORT",   {"~B", [Port]}},
           {"RABBITMQ_PID_FILE",    PidFile},
           {"RABBITMQ_ALLOW_INPUT", "1"}, %% Needed to make it close on our exit
           {"RABBITMQ_ENABLED_PLUGINS_FILE", "/does-not-exist"}],
          "../rabbitmq-server/scripts/rabbitmq-server"),
    execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s wait ~s",
             [Nodename, PidFile]}),
    Node = rabbit_nodes:make(Nodename),
    OSPid = rpc:call(Node, os, getpid, []),
    [{node,       Node},
     {pid_file,   PidFile}, 
     {os_pid,     OSPid},
     {linked_pid, Linked} | Cfg].

build_cluster([First | Rest]) ->
    add_to_cluster([First], Rest).

add_to_cluster([First | _] = Existing, New) ->
    [cluster_with(First, Node) || Node <- New],
    Existing ++ New.

cluster_with(Cfg, NewCfg) ->
    Node = pget(node, Cfg),
    NewNodename = pget(nodename, NewCfg),
    execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s stop_app",
             [NewNodename]}),
    execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s join_cluster ~s",
             [NewNodename, Node]}),
    execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s start_app",
             [NewNodename]}).   

set_default_policies(Nodes) ->
    Node = pget(node, hd(Nodes)),
    Members = [pget(node, Cfg) || Cfg <- Nodes],
    set_policy(Node, <<"^ha.all.">>, <<"all">>),
    set_policy(Node, <<"^ha.nodes.">>, <<"nodes">>, [a2b(M) || M <- Members]),
    TwoNodes = [a2b(M) || M <- lists:sublist(Members, 2)],
    set_policy(Node, <<"^ha.two.">>, <<"nodes">>, TwoNodes),
    set_policy(Node, <<"^ha.auto.">>, <<"nodes">>, TwoNodes, <<"automatic">>),
    Nodes.

start_connections(Nodes) -> [start_connection(Node) || Node <- Nodes].

start_connection(Cfg) ->
    Port = pget(port, Cfg),
    {ok, Conn} = amqp_connection:start(#amqp_params_network{port = Port}),
    {ok, Ch} =  amqp_connection:open_channel(Conn),
    [{connection, Conn}, {channel, Ch} | Cfg].

stop_nodes(Nodes) -> [stop_node(Node) || Node <- Nodes].

stop_node(Cfg) ->
    catch execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s stop ~s",
                   [pget(nodename, Cfg), pget(pid_file, Cfg)]}).

kill_node(Cfg) ->
    catch execute({"kill -9 ~s", [pget(os_pid, Cfg)]}).

%%----------------------------------------------------------------------------

execute(Cmd) -> execute([], Cmd).

execute(Env0, Cmd0) ->
    Env = [{K, fmt(V)} || {K, V} <- Env0],
    Cmd = fmt(Cmd0),
    Port = erlang:open_port(
             {spawn, "/usr/bin/env sh -c \"" ++ Cmd ++ "\""},
             [{env, Env}, exit_status,
              stderr_to_stdout, use_stdio]),
    port_receive_loop(Port, "").

port_receive_loop(Port, Stdout) ->
    receive
        {Port, {exit_status, 0}}   -> ok;
        {Port, {exit_status, 137}} -> ok; %% [0]
        {Port, {exit_status, X}}   -> exit({exit_status, X, Stdout});
        {Port, {data, Out}}        -> port_receive_loop(Port, Stdout ++ Out)
    end.

%% [0] code 137 -> killed with SIGKILL which we do in some tests

execute_bg(Env, Cmd) ->
    spawn_link(fun () ->
                       execute(Env, Cmd),
                       {links, Links} = process_info(self(), links),
                       [unlink(L) || L <- Links]
               end).

fmt({Fmt, Args}) -> rabbit_misc:format(Fmt, Args);
fmt(Str)         -> Str.

recursive_delete(Dir) -> execute({"rm -rf ~s", [Dir]}).

basedir() -> "/tmp/rabbitmq-multi-node".
