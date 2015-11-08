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
%% Copyright (c) 2007-2015 Pivotal Software, Inc.  All rights reserved.
%%
-module(rabbit_ctl_timeout_tests).

-compile([export_all]).

-export([all_tests/0]).

-import(rabbit_tests,[control_action/2, control_action/3,
                      control_action_t/3, control_action_t/4,
                      control_action_t/5, control_action_opts/1, test_channel/0,
                      find_listener/0, info_action_t/4]).

-include("rabbit.hrl").

-define(TIMEOUT_LIST_OPS_PASS, 1000).

all_tests() ->
    passed = test_list_operations_timeout_pass(),
    passed.

test_list_operations_timeout_pass() ->
    %% create a few things so there is some useful information to list
    {_Writer1, Limiter1, Ch1} = test_channel(),
    {_Writer2, Limiter2, Ch2} = test_channel(),

    [Q, Q2] = [Queue || Name <- [<<"foo">>, <<"bar">>],
                        {new, Queue = #amqqueue{}} <-
                            [rabbit_amqqueue:declare(
                               rabbit_misc:r(<<"/">>, queue, Name),
                               false, false, [], none)]],

    ok = rabbit_amqqueue:basic_consume(
           Q, true, Ch1, Limiter1, false, 0, <<"ctag1">>, true, [], undefined),
    ok = rabbit_amqqueue:basic_consume(
           Q2, true, Ch2, Limiter2, false, 0, <<"ctag2">>, true, [], undefined),

    %% list users
    ok = control_action(add_user, ["foo", "bar"]),
    {error, {user_already_exists, _}} =
        control_action(add_user, ["foo", "bar"]),
    ok = control_action_t(list_users, [], ?TIMEOUT_LIST_OPS_PASS),

    %% list parameters
    ok = rabbit_runtime_parameters_test:register(),
    ok = control_action(set_parameter, ["test", "good", "123"]),
    ok = control_action_t(list_parameters, [], ?TIMEOUT_LIST_OPS_PASS),
    ok = control_action(clear_parameter, ["test", "good"]),
    rabbit_runtime_parameters_test:unregister(),

    %% list vhosts
    ok = control_action(add_vhost, ["/testhost"]),
    {error, {vhost_already_exists, _}} =
        control_action(add_vhost, ["/testhost"]),
    ok = control_action_t(list_vhosts, [], ?TIMEOUT_LIST_OPS_PASS),

    %% list permissions
    ok = control_action(set_permissions, ["foo", ".*", ".*", ".*"],
                        [{"-p", "/testhost"}]),
    ok = control_action_t(list_permissions, [], [{"-p", "/testhost"}],
                          ?TIMEOUT_LIST_OPS_PASS),

    %% list user permissions
    ok = control_action_t(list_user_permissions, ["foo"],
                          ?TIMEOUT_LIST_OPS_PASS),

    %% list policies
    ok = control_action_opts(["set_policy", "name", ".*",
                              "{\"ha-mode\":\"all\"}"]),
    ok = control_action_t(list_policies, [], ?TIMEOUT_LIST_OPS_PASS),
    ok = control_action(clear_policy, ["name"]),

    %% list queues
    ok = info_action_t(list_queues, rabbit_amqqueue:info_keys(), false,
                       ?TIMEOUT_LIST_OPS_PASS),

    %% list exchanges
    ok = info_action_t(list_exchanges, rabbit_exchange:info_keys(), true,
                       ?TIMEOUT_LIST_OPS_PASS),

    %% list bindings
    ok = info_action_t(list_bindings, rabbit_binding:info_keys(), true,
                       ?TIMEOUT_LIST_OPS_PASS),

    %% list connections
    {H, P} = find_listener(),
    {ok, C1} = gen_tcp:connect(H, P, [binary, {active, false}]),
    gen_tcp:send(C1, <<"AMQP", 0, 0, 9, 1>>),
    {ok, <<1,0,0>>} = gen_tcp:recv(C1, 3, 100),

    {ok, C2} = gen_tcp:connect(H, P, [binary, {active, false}]),
    gen_tcp:send(C2, <<"AMQP", 0, 0, 9, 1>>),
    {ok, <<1,0,0>>} = gen_tcp:recv(C2, 3, 100),

    ok = info_action_t(list_connections,
                       rabbit_networking:connection_info_keys(),
                       false,
                       ?TIMEOUT_LIST_OPS_PASS),

    %% list consumers
    ok = info_action_t(list_consumers, rabbit_amqqueue:consumer_info_keys(),
                       false, ?TIMEOUT_LIST_OPS_PASS),

    %% list channels
    ok = info_action_t(list_channels, rabbit_channel:info_keys(), false,
                       ?TIMEOUT_LIST_OPS_PASS),

    %% do some cleaning up
    ok = control_action(delete_user, ["foo"]),
    {error, {no_such_user, _}} =
        control_action(delete_user, ["foo"]),

    ok = control_action(delete_vhost, ["/testhost"]),
    {error, {no_such_vhost, _}} =
        control_action(delete_vhost, ["/testhost"]),

    %% close_connection
    Conns = rabbit_networking:connections(),
    [ok = control_action(close_connection, [rabbit_misc:pid_to_string(ConnPid),
                                           "go away"]) || ConnPid <- Conns],

    %% cleanup queues
    [{ok, _} = rabbit_amqqueue:delete(QR, false, false) || QR <- [Q, Q2]],

    [begin
         unlink(Chan),
         ok = rabbit_channel:shutdown(Chan)
     end || Chan <- [Ch1, Ch2]],

    passed.
