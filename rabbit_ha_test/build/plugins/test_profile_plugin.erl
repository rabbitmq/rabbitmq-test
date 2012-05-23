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
-module(test_profile_plugin).

-export(['ha-test'/2]).

-define(NO_SYSTEST_LIB,
       "~n"
       "======================================================~n"
       " The 'ha-test' command requires the nebularis/systest~n"
       " library to be present on the code path.             ~n"
       " Download the latest tarball release from github~n"
       "    http://github.com/nebularis/systest~n"
       " or run `rebar -C dependencies.config get-deps compile`~n"
       " to install it to the ./lib directory locally.         ~n"
       "======================================================~n~n").

%%
%% Public (Callable) Rebar API
%%

'ha-test'(Config, _) ->
    Cwd = rebar_utils:get_cwd(),
    case is_base_dir(Cwd) of
        false ->
            rebar_log:log(debug, "skipping ~p in ~s", [?MODULE, Cwd]);
        true ->
            case code:which(systest) of
                non_existing   -> rebar_log:log(error, ?NO_SYSTEST_LIB, []);
                _SomehowLoaded -> run_ha_tests(Config)
            end
    end.

%%
%% Private API
%%

run_ha_tests(Config) ->
    ScratchDir = case os:getenv("RABBITMQ_SCRATCH_DIR") of
                     false -> filename:join(temp_dir(), "rabbit_ha_test");
                     Dir   -> Dir
                 end,
    rebar_file_utils:rm_rf(ScratchDir),
    filelib:ensure_dir(filename:join(ScratchDir, "foo")),
    rebar_config:set_global(scratch_dir, ScratchDir),
    
    Profile = case os:getenv("RABBITMQ_TEST_PROFILE") of
                  false -> os:getenv("USER");
                  Name -> Name
              end,
    Spec = case rebar_utils:find_files("profiles", Profile ++ "\\.spec") of
               [SpecFile] -> SpecFile;
               _          -> filename:join("profiles", "default.spec")
           end,
    
    Env = clean_config_dirs(Config) ++ rebar_env() ++ os_env(Config),
    {ok, SpecOutput} = transform_file(Spec, temp_dir(), Env),
    
    {ok, FinalSpec} = process_config_files(ScratchDir, SpecOutput, Env),
    
    FinalConfig = rebar_config:set(Config, ct_extra_params,
                                   "-spec " ++ FinalSpec),
    rebar_core:process_commands([ct], FinalConfig).

process_config_files(ScratchDir, TempSpec, Env) ->
    {ok, Terms} = file:consult(TempSpec),
    {[Configs], Rest} = proplists:split(Terms, [config]),
    rebar_log:log(debug, "Processing config sections: ~p~n", [Configs]),
    Replacements = [begin
                        {ok, Path} = transform_file(F, ScratchDir, Env),
                        {config, Path}
                    end || {_, F} <- lists:flatten(Configs)],
    Spec = filename:join(ScratchDir, filename:basename(TempSpec)),
    {ok, Fd} = file:open(Spec, [append]),
    Content = Replacements ++ Rest,
    rebar_log:log(debug, "Write to ~s: ~p~n", [Spec, Content]),
    write_terms(Content, Fd),
    {ok, Spec}.

transform_file(File, ScratchDir, Env) ->
    case filelib:is_regular(File) of
        false -> rebar_utils:abort("File ~s not found.~n", [File]);
        true  -> ok
    end,
    Output = filename:join(ScratchDir, filename:basename(File)),
    Target = filename:absname(Output),
    Origin = filename:absname(File),
    rebar_log:log(info, "transform ~s into ~s~n", [Origin, Target]),
    
    %% this looks *pointless* but avoids calling dict:to_list/1
    %% unless it is actually going to use the result
    case rebar_log:get_level() of
        debug -> rebar_log:log(debug, "template environment: ~p~n", [Env]);
        _     -> ok
    end,
    
    Context = rebar_templater:resolve_variables(Env, dict:new()),
    {ok, Bin} = file:read_file(File),
    Rendered = rebar_templater:render(Bin, Context),
    
    file:write_file(Output, Rendered),
    {ok, Target}.

write_terms(Terms, Fd) ->
    try
        [begin
            Element = lists:flatten(erl_pp:expr(erl_parse:abstract(Item))),
            Term = Element ++ ".\n",
            ok = file:write(Fd, Term)
         end || Item <- Terms]
    after
        file:close(Fd)
    end.

temp_dir() ->
    %% TODO: move this into hyperthunk/rebar_plugin_manager?
    case os:type() of
        {win32, _} ->
            %% mirrors the behaviour of the win32 GetTempPath function...
            get("TMP", get("TEMP", element(2, file:get_cwd())));
        _ ->
            case os:getenv("TMPDIR") of
                false -> "/tmp"; %% this is what the JVM does, but honestly...
                Dir   -> Dir
            end
    end.

get(Var, Default) ->
    case os:getenv(Var) of
        false -> Default;
        Value -> Value
    end.

is_base_dir(Cwd) ->
    Cwd == rebar_config:get_global(base_dir, undefined).

clean_config_dirs(Config) ->
    [{plugin_dir, rebar_config:get_local(Config, plugin_dir, "")}] ++
    rebar_config:get_env(Config, rebar_deps).

rebar_env() ->
    [{base_dir, rebar_config:get_global(base_dir, rebar_utils:get_cwd())}] ++
    clean_env(application:get_all_env(rebar_global)).

os_env(Config) ->
    rebar_config:get_env(Config, rebar_port_compiler).

clean_env(Env) ->
   [ E || {_, [H|_]}=E <- Env, is_integer(H) ].
