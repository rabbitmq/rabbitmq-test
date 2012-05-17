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
-module(cli_test).

-compile(export_all).

rabbit_pidfile() ->
    os:getenv("RABBITMQ_PID_FILE").

rabbit_env() ->
    case get(rabbitmq_env) of
        {env, Env} -> Env;
        _Other     -> Env = [split(Env) || Env <- os:getenv()],
                      put(rabbitmq_env, {env, Env}),
                      Env
    end.

node_name(Name) ->
    rabbit_nodes:make({atom_to_list(Name), host_shortname()}).

host_shortname() ->
    os:getenv("HOST_SHORTNAME").

split(Env) ->
    list_to_tuple(re:split(Env, "=", [{return,list},{parts,2}])).

run_daemon() ->
    Pid = spawn(fun() -> run_server(non_interactive(rabbit_env())) end),
    timer:sleep(1000),
    Pid.

run_interactive() ->
    Pid = spawn(fun() -> run_server(rabbit_env()) end),
    timer:sleep(1000),
    Pid.

non_interactive(Env) ->
    [{"RABBITMQ_ALLOW_INPUT", ""}|Env].

run_server(Env) ->
    retest:sh("scripts/rabbitmq-server", [{dir, "broker"}, {env, Env}]).

