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
-module(rabbit_test_utils).

-include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

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
    ok = rpc_call(Node, rabbit_policy, set,
                  [<<"/">>, Pattern, Pattern, Definition, 0, <<"queues">>]).

clear_policy(Node, Pattern) ->
    ok = rpc_call(Node, rabbit_policy, delete, [<<"/">>, Pattern]).

control_action(Command, Node) ->
    control_action(Command, Node, [], []).

control_action(Command, Node, Args) ->
    control_action(Command, Node, Args, []).

control_action(Command, Node, Args, Opts) ->
    rpc_call(Node, rabbit_control_main, action,
             [Command, Node, Args, Opts,
              fun (F, A) ->
                      error_logger:info_msg(F ++ "~n", A)
              end]).

cluster_status(Node) ->
    {rpc_call(Node, rabbit_mnesia, cluster_nodes, [all]),
     rpc_call(Node, rabbit_mnesia, cluster_nodes, [disc]),
     rpc_call(Node, rabbit_mnesia, cluster_nodes, [running])}.

stop_app(Node) ->
    control_action(stop_app, Node).

start_app(Node) ->
    control_action(start_app, Node).

connect({_Node, Cfg}) ->
    Port = proplists:get_value(port, Cfg),
    {ok, Conn} = amqp_connection:start(#amqp_params_network{port = Port}),
    {ok, Ch} =  amqp_connection:open_channel(Conn),
    {Conn, Ch}.

%%----------------------------------------------------------------------------

kill_after(Time, Node, Nodes, Method) ->
    timer:sleep(Time),
    kill(Node, Nodes, Method).

kill(Node, Nodes, Method) ->
    kill({Node, proplists:get_value(Node, Nodes)}, Method),
    wait_down(Node).

kill(NodeCfg, stop)    -> rabbit_test_configs:stop_node(NodeCfg);
kill(NodeCfg, sigkill) -> rabbit_test_configs:kill_node(NodeCfg).

wait_down(Node) ->
    case net_adm:ping(Node) of
        pong -> timer:sleep(25),
                wait_down(Node);
        pang -> ok
    end.

rpc_call(N, M, F, A) -> rpc:call(rabbit_nodes:make(N), M, F, A).

a2b(A) -> list_to_binary(atom_to_list(A)).

%%----------------------------------------------------------------------------

get_cfg(Name, Props) ->
    get_cfg0(string:tokens(Name, "."), Props).

get_cfg0([],      Thing) -> Thing;
get_cfg0([H | T], Props) -> K = list_to_atom(H),
                            case proplists:get_value(K, Props) of
                                undefined -> exit({cfg_not_found, K, Props});
                                Thing     -> get_cfg0(T, Thing)
                            end.
