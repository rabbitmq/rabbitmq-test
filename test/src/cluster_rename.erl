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
-module(cluster_rename).

-compile(export_all).
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-import(rabbit_misc, [pget/2]).

rename_cluster_one_by_one_with() -> cluster_abc.
rename_cluster_one_by_one([Bugs, Bigwig, Peter]) ->
    publish(Bugs,   <<"bugs">>),
    publish(Bigwig, <<"bigwig">>),
    publish(Peter,  <<"peter">>),

    Jessica = rabbit_test_configs:start_node(
                rename_node(rabbit_test_configs:stop_node(Bugs),   jessica)),
    Hazel   = rabbit_test_configs:start_node(
                rename_node(rabbit_test_configs:stop_node(Bigwig), hazel)),
    Flopsy  = rabbit_test_configs:start_node(
                rename_node(rabbit_test_configs:stop_node(Peter),  flopsy)),

    consume(Jessica, <<"bugs">>),
    consume(Hazel,   <<"bigwig">>),
    consume(Flopsy,  <<"peter">>),
    stop_all([Jessica, Hazel, Flopsy]),
    ok.

rename_cluster_big_bang_with() -> cluster_abc.
rename_cluster_big_bang([Bugs, Bigwig, Peter]) ->
    publish(Bugs,   <<"bugs">>),
    publish(Bigwig, <<"bigwig">>),
    publish(Peter,  <<"peter">>),

    Bugs1   = rabbit_test_configs:stop_node(Bugs),
    Bigwig1 = rabbit_test_configs:stop_node(Bigwig),
    Peter1  = rabbit_test_configs:stop_node(Peter),
    Jessica0 = rename_node(Bugs1,   jessica, [bigwig, hazel, peter, flopsy]),
    Hazel0   = rename_node(Bigwig1, hazel,   [bugs, jessica, peter, flopsy]),
    Flopsy0  = rename_node(Peter1,  flopsy,  [bugs, jessica, bigwig, hazel]),
    Jessica = rabbit_test_configs:start_node(Jessica0),
    Hazel   = rabbit_test_configs:start_node(Hazel0),
    Flopsy  = rabbit_test_configs:start_node(Flopsy0),

    consume(Jessica, <<"bugs">>),
    consume(Hazel,   <<"bigwig">>),
    consume(Flopsy,  <<"peter">>),
    stop_all([Jessica, Hazel, Flopsy]),
    ok.

abortive_rename_with() -> cluster_ab.
abortive_rename([Bugs, _Bigwig]) ->
    publish(Bugs,  <<"bugs">>),

    Bugs1   = rabbit_test_configs:stop_node(Bugs),
    _Jessica = rename_node(Bugs1, jessica),
    Bugs2 = rabbit_test_configs:start_node(Bugs1),

    consume(Bugs2, <<"bugs">>),
    ok.

rename_twice_with() -> cluster_ab.
rename_twice([Bugs, _Bigwig]) ->
    publish(Bugs,  <<"bugs">>),

    Bugs1 = rabbit_test_configs:stop_node(Bugs),
    _Indecisive = rename_node(Bugs1, indecisive),
    Jessica = rabbit_test_configs:start_node(rename_node(Bugs1, jessica)),

    consume(Jessica, <<"bugs">>),
    stop_all([Jessica]),
    ok.

rename_fail_with() -> cluster_ab.
rename_fail([Bugs, _Bigwig]) ->
    Bugs1 = rabbit_test_configs:stop_node(Bugs),
    rename_node_fail(Bugs1, bugzilla, jessica, []),
    ok.

%% ----------------------------------------------------------------------------

%% Normal post-test stop does not work since names have changed...
stop_all(Cfgs) ->
     [rabbit_test_configs:stop_node(Cfg) || Cfg <- Cfgs].

rename_node(Cfg, Nodename) -> rename_node(Cfg, Nodename, []).

rename_node(Cfg, Nodename, Extra) ->
    rename_node(Cfg, pget(nodename, Cfg), Nodename, Extra,
                fun rabbit_test_configs:rabbitmqctl/2).

rename_node_fail(Cfg, OldNodename, Nodename, Extra) ->
    rename_node(Cfg, OldNodename, Nodename, Extra,
                fun rabbit_test_configs:rabbitmqctl_fail/2).

rename_node(Cfg, OldNodename, Nodename, Extra, Ctl) ->
    ExtraS = string:join(
               [atom_to_list(rabbit_nodes:make(N)) || N <- Extra], " "),
    OldNode = rabbit_nodes:make(OldNodename),
    Node = rabbit_nodes:make(Nodename),
    NewCfg = [{nodename, Nodename} | proplists:delete(nodename, Cfg)],
    Ctl(NewCfg, {"rename_cluster_node ~s ~s ~s", [OldNode, Node, ExtraS]}),
    NewCfg.

publish(Cfg, Q) ->
    Ch = pget(channel, Cfg),
    amqp_channel:call(Ch, #'confirm.select'{}),
    amqp_channel:call(Ch, #'queue.declare'{queue = Q, durable = true}),
    amqp_channel:cast(Ch, #'basic.publish'{routing_key = Q},
                      #amqp_msg{props   = #'P_basic'{delivery_mode = 2},
                                payload = Q}),
    amqp_channel:wait_for_confirms(Ch).

consume(Cfg, Q) ->
    {_Conn, Ch} = rabbit_test_util:connect(Cfg),
    amqp_channel:call(Ch, #'queue.declare'{queue = Q, durable = true}),
    {#'basic.get_ok'{}, #amqp_msg{payload = Q}} =
        amqp_channel:call(Ch, #'basic.get'{queue = Q}).
