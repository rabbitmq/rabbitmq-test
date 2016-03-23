-module(rabbit_config_schema_test).

-compile(export_all).
-include_lib("eunit/include/eunit.hrl").

run_snippets_test() ->
    SchemaDir = "schema",
    setup(SchemaDir),
    ok = run_snippets("test/snippets.config", SchemaDir),
    cleanup().

setup(SchemaDir) ->
    %% Create directories and files so that the snippets can pass validation
    file:make_dir("example_files"),
    file:make_dir("example_files/tmp"),
    file:make_dir("example_files/tmp/rabbit-mgmt"),
    file:make_dir("example_files/path"),
    file:make_dir("example_files/path/to"),
    file:write_file("example_files/path/to/cacert.pem", "I'm not a certificate"),
    file:write_file("example_files/path/to/cert.pem", "I'm not a certificate"),
    file:write_file("example_files/path/to/key.pem", "I'm not a certificate"),
    file:make_dir(SchemaDir),
    prepare_plugin_schemas(SchemaDir).

cleanup() ->
    rabbit_file:recursive_delete(["example_files", "examples", "schema", "generated"]).

run_snippets(FileName, SchemaDir) ->
    {ok, [Snippets]} = file:consult(FileName),
    lists:map(
        fun({N, S, C, P})    -> ok = test_snippet({integer_to_list(N), S, []}, C, P, SchemaDir);
           ({N, S, A, C, P}) -> ok = test_snippet({integer_to_list(N), S, A},  C, P, SchemaDir)
        end,
        Snippets),
    ok.

test_snippet(Snippet, Expected, Plugins, SchemaDir) ->
    {Conf, Advanced} = write_snippet(Snippet),
    rabbit_file:recursive_delete("generated"),
    {ok, GeneratedFile} = generate_config(Conf, Advanced, SchemaDir),
    {ok, [Generated]} = file:consult(GeneratedFile),
    Gen = deepsort(Generated),
    Exp = deepsort(Expected),
    case Exp of
        Gen -> ok;
        _         -> 
            error({config_mismatch, Snippet, Exp, Gen})
    end.

write_snippet({Name, Config, Advanced}) ->
    rabbit_file:recursive_delete(filename:join(["examples", Name])),
    file:make_dir("examples"),
    file:make_dir(filename:join(["examples", Name])),
    ConfFile = filename:join(["examples", Name, "config.conf"]),
    AdvancedFile = filename:join(["examples", Name, "advanced.config"]),

    file:write_file(ConfFile, Config),
    rabbit_file:write_term_file(AdvancedFile, [Advanced]),
    {ConfFile, AdvancedFile}.
    

generate_config(Conf, Advanced, SchemaDir) ->
    ScriptDir = case init:get_argument(conf_script_dir) of
        {ok, D} -> D;
        _       -> "../rabbit/scripts"
    end,
    rabbit_config:generate_config_file([Conf], ".", ScriptDir, 
                                       SchemaDir, Advanced).

prepare_schemas(Plugins) ->
    {ok, EnabledFile} = application:get_env(rabbit, enabled_plugins_file),
    rabbit_file:write_term_file(EnabledFile, [Plugins]).

prepare_plugin_schemas(SchemaDir) ->
    Files = filelib:wildcard("../*/priv/schema/*.schema"),
    [ file:copy(File, filename:join([SchemaDir, filename:basename(File)])) 
        || File <- Files ].


deepsort(List) ->
    case is_proplist(List) of
        true ->
            lists:keysort(1, lists:map(fun({K, V}) -> {K, deepsort(V)};
                                          (V) -> V end,
                                       List));
        false -> 
            case is_list(List) of
                true  -> lists:sort(List);
                false -> List
            end
    end.

is_proplist([{_K, _V}|_] = List) -> lists:all(fun({_K, _V}) -> true; (_) -> false end, List);
is_proplist(_) -> false.
