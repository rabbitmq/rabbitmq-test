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
-module(ctl_status_rt).

-compile(export_all).

-include("../common.hrl").
-include_lib("eunit/include/eunit.hrl").

files() ->
    [{copy, ?RABBITMQ_BROKER_DIR, "broker"}].

run(_Dir) ->
    Env = cli_test:rabbit_env(),
    PidFile = cli_test:rabbit_pidfile(),
    Node = cli_test:node_name(rabbit),

    ServerPid = cli_test:run_interactive(),

    retest:log(info, "Wait for rabbit using ~s~n", [PidFile]),
    ?assertMatch({ok, _},
                 retest:sh("scripts/rabbitmqctl wait " ++ PidFile,
                           [{dir, "broker"}, {env, Env}])),

    retest:log(info, "Checking status of ~p using rabbitmqctl~n", [Node]),
    Ref = retest:sh("scripts/rabbitmqctl status",
                    [{dir, "broker"}, {env, Env}, {async, true}]),

    retest:sh_expect(Ref, "status of node .*"
                          "{running_applications,\\[\\{rabbit,"
                          "\"RabbitMQ\", .* done",
                          [multiline, {newline, any}]),

    retest:log(info, "Shut down rabbit server...~n", []),
    ?assertMatch({ok, _}, retest:sh("scripts/rabbitmqctl stop",
                                    [{dir, "broker"}, {env, Env}])),
    ?assertMatch({badrpc,nodedown},
                 rpc:call(Node, rabbit, is_running, [])),

    retest:log(info, "Performing brutal (kill -9) shutdown~n", []),
    retest_sh:kill_all(),
    exit(ServerPid, kill),
    ok.

