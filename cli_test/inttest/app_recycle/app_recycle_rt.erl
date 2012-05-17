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
-module(app_recycle_rt).

-compile(export_all).

-include("../common.hrl").
-include_lib("eunit/include/eunit.hrl").

files() ->
    [{copy, ?RABBITMQ_BROKER_DIR, "broker"}].

run(Dir) ->
    Env = cli_test:rabbit_env(),
    PidFile = cli_test:rabbit_pidfile(),
    Node = cli_test:node_name(rabbit),
    retest:log(info, "Node = ~p~n", [Node]),

    spawn(fun() -> run_server(Env) end),
    timer:sleep(1000),

    retest:log(info, "Wait for rabbit using ~s~n", [PidFile]),
    ?assertMatch({ok, _},
                 retest:sh("scripts/rabbitmqctl wait " ++ PidFile,
                           [{dir, "broker"}, {env, Env}])),

    retest:log(info, "Stop rabbit app on ~p~n", [Node]),
    ?assertMatch({ok, _},
              retest:sh("scripts/rabbitmqctl stop_app",
                        [{dir, "broker"}, {env, Env}])),
    ?assertMatch(false, rpc:call(Node, rabbit, is_running, [])),

    retest:log(info, "Start rabbit app on ~p~n", [Node]),
    ?assertMatch({ok, _},
              retest:sh("scripts/rabbitmqctl start_app",
                        [{dir, "broker"}, {env, Env}])),
    ?assertMatch(true, rpc:call(Node, rabbit, is_running, [])),

    retest:log(info, "Shut down rabbit server...~n", []),
    ?assertMatch({ok, _}, retest:sh("scripts/rabbitmqctl stop",
                                    [{dir, "broker"}, {env, Env}])),
    ?assertMatch({badrpc,nodedown},
                 rpc:call(Node, rabbit, is_running, [])),
    ok.

run_server(Env) ->
    retest:sh("scripts/rabbitmq-server",
              [{dir, "broker"}, {env, [{"RABBITMQ_ALLOW_INPUT", ""}|Env]}]).

