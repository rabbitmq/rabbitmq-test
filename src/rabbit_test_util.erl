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
-module(rabbit_test_util).

-include_lib("amqp_client/include/amqp_client.hrl").
-import(rabbit_misc, [pget/2]).

-compile(export_all).

set_ha_policy(Cfg, Pattern, HAMode) ->
    set_policy(Cfg, Pattern, Pattern, <<"queues">>,
               [{<<"ha-mode">>,   HAMode}]).

set_ha_policy(Cfg, Pattern, HAMode, HAParams) ->
    set_policy(Cfg, Pattern, Pattern, <<"queues">>,
               [{<<"ha-mode">>,   HAMode},
                {<<"ha-params">>, HAParams}]).

set_ha_policy(Cfg, Pattern, HAMode, HAParams, HASyncMode) ->
    set_policy(Cfg, Pattern, Pattern, <<"queues">>,
               [{<<"ha-mode">>,      HAMode},
                {<<"ha-params">>,    HAParams},
                {<<"ha-sync-mode">>, HASyncMode}]).

set_policy(Cfg, Name, Pattern, ApplyTo, Definition) ->
    ok = rpc:call(pget(node, Cfg), rabbit_policy, set,
                  [<<"/">>, Name, Pattern, Definition, 0, ApplyTo]).

clear_policy(Cfg, Name) ->
    ok = rpc:call(pget(node, Cfg), rabbit_policy, delete, [<<"/">>, Name]).

set_param(Cfg, Component, Name, Value) ->
    ok = rpc:call(pget(node, Cfg), rabbit_runtime_parameters, set,
                  [<<"/">>, Component, Name, Value, none]).

clear_param(Cfg, Component, Name) ->
    ok = rpc:call(pget(node, Cfg), rabbit_runtime_parameters, clear,
                 [<<"/">>, Component, Name]).

control_action(Command, Cfg) ->
    control_action(Command, Cfg, [], []).

control_action(Command, Cfg, Args) ->
    control_action(Command, Cfg, Args, []).

control_action(Command, Cfg, Args, Opts) ->
    Node = pget(node, Cfg),
    rpc:call(Node, rabbit_control_main, action,
             [Command, Node, Args, Opts,
              fun (F, A) ->
                      error_logger:info_msg(F ++ "~n", A)
              end]).

restart_app(Cfg) ->
    stop_app(Cfg),
    start_app(Cfg).

stop_app(Cfg) ->
    control_action(stop_app, Cfg).

start_app(Cfg) ->
    control_action(start_app, Cfg).

connect(Cfg) ->
    Port = pget(port, Cfg),
    {ok, Conn} = amqp_connection:start(#amqp_params_network{port = Port}),
    {ok, Ch} =  amqp_connection:open_channel(Conn),
    {Conn, Ch}.

%%----------------------------------------------------------------------------

kill_after(Time, Cfg, Method) ->
    timer:sleep(Time),
    kill(Cfg, Method).

kill(Cfg, Method) ->
    kill0(Cfg, Method),
    wait_down(pget(node, Cfg)).

kill0(Cfg, stop)    -> rabbit_test_configs:stop_node(Cfg);
kill0(Cfg, sigkill) -> rabbit_test_configs:kill_node(Cfg).

wait_down(Node) ->
    case net_adm:ping(Node) of
        pong -> timer:sleep(25),
                wait_down(Node);
        pang -> ok
    end.

a2b(A) -> list_to_binary(atom_to_list(A)).
