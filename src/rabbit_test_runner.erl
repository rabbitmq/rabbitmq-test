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

-module(rabbit_test_runner).

-include_lib("kernel/include/file.hrl").

-define(TIMEOUT, 600).

-import(rabbit_misc, [pget/2]).

-export([run_multi/4]).

run_multi(Dir, Filter, Cover, PluginsDir) ->
    io:format("~nMulti-node tests~n================~n~n", []),
    %% Umbrella does not give us -sname
    net_kernel:start([?MODULE, shortnames]),
    error_logger:tty(false),
    case Cover of
        true  -> io:format("Cover compiling..."),
                 cover:start(),
                 ok = rabbit_misc:enable_cover(["../rabbitmq-server/"]),
                 io:format(" done.~n~n");
        false -> ok
    end,
    ok = eunit:test(make_tests(Dir, Filter, Cover, PluginsDir, ?TIMEOUT), []),
    case Cover of
        true  -> io:format("~nCover reporting..."),
                 ok = rabbit_misc:report_cover(),
                 io:format(" done.~n~n");
        false -> ok
    end,
    ok.

make_tests(Dir, Filter, Cover, PluginsDir, Timeout) ->
    All = [{M, FWith, F} ||
              M <- modules(Dir),
              {FWith, _Arity} <- proplists:get_value(exports, M:module_info()),
              string:right(atom_to_list(FWith), 5) =:= "_with",
              F <- [fwith_to_f(FWith)]],
    Filtered = [Test || {M, _FWith, F} = Test <- All,
                        should_run(M, F, tokens(Filter))],
    io:format("Running ~B of ~B tests; FILTER=~s; COVER=~s~n~n",
              [length(Filtered), length(All), Filter, Cover]),
    Width = case Filtered of
                [] -> 0;
                _  -> lists:max([atom_length(F) || {_, _, F} <- Filtered])
            end,
    Cfg = [{cover,   Cover},
           {base,    basedir() ++ "/nodes"},
           {plugins, PluginsDir}],
    rabbit_test_configs:enable_plugins(PluginsDir),
    [make_test(M, FWith, F, ShowHeading, Timeout, Width, Cfg)
     || {M, FWith, F, ShowHeading} <- annotate_show_heading(Filtered)].

make_test(M, FWith, F, ShowHeading, Timeout, Width, InitialCfg) ->
    {setup,
     fun () ->
             case ShowHeading of
                 true  -> io:format(user, "~n~s~n~s~n",
                                    [M, string:chars($-, atom_length(M))]);
                 false -> ok
             end,
             io:format(user, "~s [setup]", [name(F, Width)]),
             setup_error_logger(M, F, basedir()),
             recursive_delete(pget(base, InitialCfg)),
             CfgFun = case M:FWith() of
                          CfgName when is_atom(CfgName) ->
                              fun (Cfg) -> rabbit_test_configs:CfgName(Cfg) end;
                          Else ->
                              Else
                      end,
             CfgFun(InitialCfg)
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

annotate_show_heading(List) ->
    annotate_show_heading(List, undefined).

annotate_show_heading([], _) ->
    [];
annotate_show_heading([{M, FWith, F} | Rest], Current) ->
    [{M, FWith, F, M =/= Current} | annotate_show_heading(Rest, M)].

setup_error_logger(M, F, Base) ->
    case error_logger:logfile(filename) of
        {error, no_log_file} -> ok;
        _                    -> ok = error_logger:logfile(close)
    end,
    FN = rabbit_misc:format("~s/~s:~s.log", [basedir(), M, F]),
    ensure_dir(Base),
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

modules(RelDir) ->
    {ok, Files} = file:list_dir(RelDir),
    [M || F <- Files,
          M <- case string:tokens(F, ".") of
                   [MStr, "beam"] -> [list_to_atom(MStr)];
                   _              -> []
               end].

recursive_delete(Dir) ->
    rabbit_test_configs:execute({"rm -rf ~s", [Dir]}).

name(F, Width) ->
    R = atom_to_list(F),
    R ++ ":" ++ string:chars($ , Width - length(R)).

atom_length(A) -> length(atom_to_list(A)).

basedir() -> "/tmp/rabbitmq-multi-node".
