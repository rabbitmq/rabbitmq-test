%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ
%%
%%   The Initial Developer of the Original Code is GoPivotal, Inc.
%%   Copyright (c) 2010-2014 GoPivotal, Inc.  All rights reserved.
%%

-module(multi_node_test_runner).

-include_lib("kernel/include/file.hrl").

-define(TIMEOUT, 600).
%% TODO generate this
-define(MODULES, [clustering_management, dynamic_ha, eager_sync,
                  many_node_ha, partitions, simple_ha, sync_detection]).

-import(rabbit_misc, [pget/2]).

-export([run/1]).

run(Filter) ->
    %% Umbrella does not give us -sname
    net_kernel:start([multi_node_test_runner, shortnames]),
    error_logger:tty(false),
    ok = eunit:test(make_tests(Filter, ?TIMEOUT), []).

make_tests(Filter, Timeout) ->
    All = [{M, FWith, F} ||
              M <- ?MODULES,
              {FWith, _Arity} <- proplists:get_value(exports, M:module_info()),
              string:right(atom_to_list(FWith), 5) =:= "_with",
              F <- [fwith_to_f(FWith)]],
    Filtered = [Test || {M, _FWith, F} = Test <- All,
                        should_run(M, F, tokens(Filter))],
    io:format("~nMulti-node tests~n================~n~n", []),
    io:format("Running ~B of ~B tests; FILTER=~s~n~n",
              [length(Filtered), length(All), Filter]),
    Width = lists:max([length(name(M, F)) || {M, _, F} <- Filtered]),
    [make_test(M, FWith, F, Timeout, Width) || {M, FWith, F} <- Filtered].

make_test(M, FWith, F, Timeout, Width) ->
    {setup,
     fun () ->
             io:format(user, "~s [setup]", [name(M, F, Width)]),
             setup_error_logger(M, F),
             CfgFun = case M:FWith() of
                          CfgName when is_atom(CfgName) ->
                              fun rabbit_test_configs:CfgName/0;
                          Else ->
                              Else
                      end,
             CfgFun()
     end,
     fun (Nodes) ->
             rabbit_test_configs:stop_nodes(Nodes),
             io:format(user, ".~n", [])
     end,
     fun (Nodes) ->
             [{timeout,
               Timeout,
               fun () ->
                       [link(pget(linked_pid, N)) || N <- Nodes],
                       io:format(user, " [running]", []),
                       M:F(Nodes),
                       io:format(user, " [PASSED]", [])
               end}]
     end}.

setup_error_logger(M, F) ->
    case error_logger:logfile(filename) of
        {error, no_log_file} -> ok;
        _                    -> ok = error_logger:logfile(close)
    end,
    FN = rabbit_misc:format("~s/~s:~s.log",
                            [rabbit_test_configs:basedir(), M, F]),
    ensure_dir(rabbit_test_configs:basedir()),
    ok = error_logger:logfile({open, FN}).

fwith_to_f(FWith) ->
    FName = atom_to_list(FWith),
    list_to_atom(string:substr(FName, 1, length(FName) - 5)).

tokens(Filter) ->
    [list_to_atom(T) || T <- string:tokens(Filter, ":")].

should_run(_Module, _F, [all])       -> true;
should_run( Module, _F, [Module])    -> true;
should_run( Module,  F, [Module, F]) -> true;
should_run(_Module, _F, _)           -> false.

ensure_dir(Path) ->
    case file:read_file_info(Path) of
        {ok, #file_info{type=regular}}   -> exit({exists_as_file, Path});
        {ok, #file_info{type=directory}} -> ok;
        _                                -> file:make_dir(Path)
    end.

name(M, F, Width) ->
    R = name(M, F),
    R ++ string:chars($ , Width - length(R)).

name(M, F) -> rabbit_misc:format("~s:~s:", [M, F]).
