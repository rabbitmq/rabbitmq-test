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
-module(rabbit_ha_test_utils).

-include_lib("systest/include/systest.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-export([wait/1, mirror_args/1, amqp_open/1, amqp_close/1]).

wait(Node) ->
    NodeId  = systest_node:get_node_info(id, Node),
    % Flags   = systest_node:get_node_info(private, Node),
    ct:pal("Looking for pid file in ~p~n", [Node]),
    LogFun  = fun ct:pal/2,
    case node_eval("node.private.env", [{node, Node}]) of
        []  -> throw(no_pidfile);
        Env -> case lists:keyfind("RABBITMQ_PID_FILE", 1, Env) of
                   false   -> throw(no_pidfile);
                   {_, PF} -> rabbit_control_main:action(wait, NodeId,
                                                         [PF], [], LogFun)
               end
    end.

%% TODO: this *really* belongs in SysTest, not here!!!
node_eval(Key, Node) ->
    systest_config:eval(Key, Node,
                        [{callback,
                            {node, fun systest_node:get_node_info/2}}]).

mirror_args([]) ->
    [{<<"x-ha-policy">>, longstr, <<"all">>}];
mirror_args(Nodes) ->
    [{<<"x-ha-policy">>, longstr, <<"nodes">>},
     {<<"x-ha-policy-params">>, array,
      [{longstr, list_to_binary(atom_to_list(N))} || N <- Nodes]}].

amqp_close(#'systest.node_info'{user=UserData}) ->
    Channel = ?CONFIG(amqp_channel, UserData, undefined),
    Connection = ?CONFIG(amqp_connection, UserData, undefined),
    close_channel(Channel),
    close_connection(Connection).

amqp_open(Node=#'systest.node_info'{user=UserData}) ->
    NodePort = ?REQUIRE(amqp_port, UserData),
    {ok, Connection} =
        amqp_connection:start(#amqp_params_network{port=NodePort}),
    Channel = open_channel(Connection),
    AmqpData = [{amqp_connection, Connection},
                {amqp_channel,    Channel}|UserData],
    systest_node:set_node_info(user, AmqpData, Node).

open_channel(Connection) ->
    {ok, Channel} = amqp_connection:open_channel(Connection),
    Channel.

close_connection(Connection) ->
    rabbit_misc:with_exit_handler(
      rabbit_misc:const(ok), fun () -> amqp_connection:close(Connection) end).

close_channel(Channel) ->
    rabbit_misc:with_exit_handler(
      rabbit_misc:const(ok), fun () -> amqp_channel:close(Channel) end).

