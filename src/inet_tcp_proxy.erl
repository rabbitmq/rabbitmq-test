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
-module(inet_tcp_proxy).

-export([start/0]).

%% This can't start_link because there's no supervision hierarchy we
%% can easily fit it into (we need to survive all application
%% restarts). So we have to do some horrible error handling.

start() -> spawn(error_handler(fun go/0)).

error_handler(Thunk) ->
    fun () ->
            try
                Thunk()
            catch _:X ->
                    io:format(user, "TCP proxy died with ~p~n At ~p~n",
                              [X, erlang:get_stacktrace()]),
                    erlang:halt(1)
            end
    end.

go() ->
    ets:new(inet_interceptable_dist, [public, named_table]),
    {ok, Port} = application:get_env(kernel, inet_dist_listen_min),
    ProxyPort = Port + 10000,
    {ok, Sock} = gen_tcp:listen(ProxyPort, [inet]),
    accept_loop(Sock, Port).

accept_loop(ListenSock, Port) ->
    {ok, Sock} = gen_tcp:accept(ListenSock),
    spawn(error_handler(fun() -> run_it(Sock, Port) end)),
    accept_loop(ListenSock, Port).

run_it(SockIn, Port) ->
    {ok, {Addr, _OtherPort}} = inet:sockname(SockIn),
    {ok, SockOut} = gen_tcp:connect(Addr, Port, [inet]),
    run_loop(SockIn, SockOut).

run_loop(SockIn, SockOut) ->
    receive
        {tcp, SockIn,  Data}  -> io:format(user, "in ~p~n", [Data]),
                                 ok = gen_tcp:send(SockOut, Data),
                                 run_loop(SockIn, SockOut);
        {tcp, SockOut, Data}  -> io:format(user, "out ~p~n", [Data]),
                                 ok = gen_tcp:send(SockIn, Data),
                                 run_loop(SockIn, SockOut);
        {tcp_closed, SockIn}  -> io:format(user, "finish in~n", []),
                                 gen_tcp:close(SockOut);
        {tcp_closed, SockOut} -> io:format(user, "finish out~n", []),
                                 gen_tcp:close(SockIn);
        X                     -> exit({got, X})
    end.
