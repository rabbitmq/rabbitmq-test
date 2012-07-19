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
-module(ha_recovery_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("systest/include/systest.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-export([all/0, init_per_suite/1,
         end_per_suite/1,
         event_log_failure_during_shutdown/1,
         bug25059_safely_shutdown/0,
         bug25059_safely_shutdown/1]).

all() -> systest_suite:export_all(?MODULE).

init_per_suite(Config) -> Config.

end_per_suite(_Config) -> ok.

event_log_failure_during_shutdown(Config) ->
    {_, [{{_, N1}, {_, MasterChannel}},
         {{_, N2}, {_, _}},
         {{_, N3}, {_, _}}] } =
                        rabbit_ha_test_utils:cluster_members(Config),

    %% declare some queues on the master, mirrored to the two slaves
    [declare_ha(MasterChannel) || _ <- lists:seq(1, 4)],

    %% now cleanly shut the nodes down in sequence...
    systest:stop_and_wait(N3),
    systest:stop_and_wait(N2),
    systest:stop_and_wait(N1),

    %% the logs should now contain traces of event publication failures
    ok.

bug25059_safely_shutdown() ->
    [{timetrap, {minutes, 2}}].

bug25059_safely_shutdown(Config) ->
    {_, [{{_, N1}, {_, MasterChannel}},
         {{_, N2}, {_, N2Chan}},
         {{_, N3}, {_, N3Chan}}] } =
                        rabbit_ha_test_utils:cluster_members(Config),

    %% declare some queues on the master, mirrored to the two slaves
    [declare_ha(MasterChannel) || _ <- lists:seq(1, 4)],

    [declare(Chan) || Chan <- [N2Chan, N3Chan], _ <- lists:seq(1, 3)],

    %% now cleanly shut the nodes down in sequence...
    systest:stop_and_wait(N1),
    systest:stop_and_wait(N2),
    systest:stop_and_wait(N3),
    ok.

declare(Channel) ->
    #'queue.declare_ok'{} =
        amqp_channel:call(Channel,
                          #'queue.declare'{auto_delete = false,
                                           durable     = true}).

declare_ha(MasterChannel) ->
    #'queue.declare_ok'{} =
        amqp_channel:call(MasterChannel,
                          #'queue.declare'{
                              auto_delete = false,
                              durable     = true,
                              arguments   = [{<<"x-ha-policy">>,
                                                longstr, <<"all">>}]}).

