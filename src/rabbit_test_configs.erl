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

-export([cluster_abc/0, cluster_abcdef/0]).
-export([start_nodes/2, add_to_cluster/2]).
-export([stop_nodes/1, stop_node/1, kill_node/1, basedir/0]).

-import(rabbit_test_utils, [set_policy/3, set_policy/4, set_policy/5, a2b/1]).

cluster_abc()    -> cluster([a, b, c]).
cluster_abcdef() -> cluster([a, b, c, d, e, f]).

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
    Nodes = [{N, [{port, P}]} || {N, P} <- lists:zip(NodeNames, Ports)],
    Base = basedir() ++ "/nodes",
    [start_node(Node, Base) || Node <- Nodes].

check_node_not_running(Node, Already) ->
    case lists:member(Node, Already) of
        true  -> exit({node_already_running, Node});
        false -> ok
    end.

start_node({Node, Cfg}, Base) ->
    Port = proplists:get_value(port, Cfg),
    PidFile = rabbit_misc:format("~s/~s.pid", [Base, Node]),
    Linked =
        execute_bg(
          [{"RABBITMQ_MNESIA_BASE", {"~s/rabbitmq-~s-mnesia", [Base, Node]}},
           {"RABBITMQ_LOG_BASE",    {"~s", [Base]}},
           {"RABBITMQ_NODENAME",    {"~s", [Node]}},
           {"RABBITMQ_NODE_PORT",   {"~B", [Port]}},
           {"RABBITMQ_PID_FILE",    PidFile},
           {"RABBITMQ_ENABLED_PLUGINS_FILE", "/does-not-exist"}],
          "../rabbitmq-server/scripts/rabbitmq-server"),
    execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s wait ~s",
             [Node, PidFile]}),
    OSPid = rpc:call(rabbit_nodes:make(Node), os, getpid, []),
    {Node, [{pid_file, PidFile}, {os_pid, OSPid}, {linked_pid, Linked} | Cfg]}.

build_cluster([First | Rest]) ->
    add_to_cluster([First], Rest).

add_to_cluster([First | _] = Existing, New) ->
    [cluster_with(First, Node) || Node <- New],
    Existing ++ New.

cluster_with({Node, _}, {NewNode, _}) ->
    execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s stop_app",
             [NewNode]}),
    execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s join_cluster ~s",
             [NewNode, rabbit_nodes:make(Node)]}),
    execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s start_app",
             [NewNode]}).   

set_default_policies(Nodes) ->
    Members = [Node | _] = [rabbit_nodes:make(N) || {N, _} <- Nodes],
    set_policy(Node, <<"^ha.all.">>, <<"all">>),
    set_policy(Node, <<"^ha.nodes.">>, <<"nodes">>, [a2b(M) || M <- Members]),
    TwoNodes = [a2b(M) || M <- lists:sublist(Members, 2)],
    set_policy(Node, <<"^ha.two.">>, <<"nodes">>, TwoNodes),
    set_policy(Node, <<"^ha.auto.">>, <<"nodes">>, TwoNodes, <<"automatic">>),
    Nodes.

start_connections(Nodes) -> [start_connection(Node) || Node <- Nodes].

start_connection({Node, Cfg}) ->
    Port = proplists:get_value(port, Cfg),
    {ok, Conn} = amqp_connection:start(#amqp_params_network{port = Port}),
    {ok, Ch} =  amqp_connection:open_channel(Conn),
    {Node, [{connection, Conn}, {channel, Ch} | Cfg]}.

stop_nodes(Nodes) -> [stop_node(Node) || Node <- Nodes].

stop_node({Node, Cfg}) ->
    PidFile = proplists:get_value(pid_file, Cfg),
    catch execute({"../rabbitmq-server/scripts/rabbitmqctl -n ~s stop ~s",
                   [Node, PidFile]}).

kill_node({_Node, Cfg}) ->
    unlink(proplists:get_value(linked_pid, Cfg)),
    catch execute({"kill -9 ~s", [proplists:get_value(os_pid, Cfg)]}).

%%----------------------------------------------------------------------------

execute(Cmd) -> execute([], Cmd).

execute(Env, Cmd0) ->
    Cmd = env_prefix(Env) ++ fmt(Cmd0) ++ " ; echo $?",
    Res = os:cmd(Cmd),
    case lists:reverse(string:tokens(Res, "\n")) of
        ["0" | _] -> ok;
        _         -> exit({command_failed, Cmd, Res})
    end.

%%execute_bg(Cmd) -> execute_bg([], Cmd).

execute_bg(Env, Cmd) ->
    Self = self(),
    spawn_link(fun () ->
                       execute(Env, Cmd),
                       unlink(Self)
               end).

env_prefix(Env) ->
    lists:append([fmt({"export ~s=~s; ", [K, fmt(V)]}) || {K, V} <- Env]).

fmt({Fmt, Args}) -> rabbit_misc:format(Fmt, Args);
fmt(Str)         -> Str.

recursive_delete(Dir) -> execute({"rm -rf ~s", [Dir]}).

basedir() -> "/tmp/rabbitmq-multi-node".
