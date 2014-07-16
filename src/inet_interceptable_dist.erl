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
-module(inet_interceptable_dist).

%% API
-export([allow/1, block/2]).

%% inet_*_dist "behaviour"
-export([listen/1, accept/1, accept_connection/5,
	 setup/5, close/1, select/1, is_node_name/1]).

-define(REAL, inet_tcp_dist).
-define(TABLE, ?MODULE).

allow(Node)        -> ets:delete(?TABLE, Node).
block(Node, Delay) -> ets:insert(?TABLE, {Node, Delay}).

listen(Name)       -> ets:new(?TABLE, [public, named_table]),
                      ?REAL:listen(Name).
select(Node)       -> ?REAL:select(Node).
accept(Listen)     -> ?REAL:accept(Listen).
close(Socket)      -> ?REAL:close(Socket).
is_node_name(Node) -> ?REAL:is_node_name(Node).

%% Inbound from another node TODO it would be nice if we could filter
%% accepts here and thus support asymmetric partitions. But we can't
%% tell which node a connection is from.
accept_connection(AcceptPid, Socket, MyNode, Allowed, SetupTime) ->
    ?REAL:accept_connection(AcceptPid, Socket, MyNode, Allowed, SetupTime).

%% Outgoing to another node
setup(Node, Type, MyNode, LongOrShortNames,SetupTime) ->
    case ets:lookup(?TABLE, Node) of
        [{Node, Delay}] ->
            error_logger:info_msg(
              "Refusing to connect to ~p with delay ~p~n", [Node, Delay]),
            spawn_link(
              fun () ->
                      timer:sleep(Delay),
                      dist_util:shutdown(?MODULE, ?LINE, blocked)
              end);
        [] ->
            ?REAL:setup(Node, Type, MyNode, LongOrShortNames,SetupTime)
    end.
