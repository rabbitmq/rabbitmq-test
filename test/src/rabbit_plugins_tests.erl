-module(rabbit_plugins_tests).
-include("rabbit.hrl").

-compile(export_all).

test_version_support() ->
    Examples = [
     {[], "any version", ok} %% anything goes
    ,{[], "0.0.0", ok}       %% ditto
    ,{[], "3.5.6", ok}       %% ditto
    ,{["something"], "something", ok}            %% equal values match
    ,{["3.5.4"], "something", err}
    ,{["something", "3.5.6"], "3.5.7", ok}       %% 3.5.7 matches ~> 3.5.6
    ,{["3.4.0", "3.5.6"], "3.6.1", err}          %% 3.6.x isn't supported
    ,{["3.5.2", "3.6.1", "3.7.1"], "3.5.2", ok}  %% 3.5.2 matches ~> 3.5.2
    ,{["3.5.2", "3.6.1", "3.7.1"], "3.5.1", err} %% lesser than the lower boundary
    ,{["3.5.2", "3.6.1", "3.7.1"], "3.6.2", ok}  %% 3.6.2 matches ~> 3.6.1
    ,{["3.5.2", "3.6.1", "3.7.1"], "0.0.0", err}
    ,{["3.5", "3.6", "3.7"], "3.5.1", err}       %% x.y values are not supported
    ,{["3"], "3.5.1", err}                       %% x values are not supported
    ],

    lists:foreach(
        fun({Versions, RabbitVersion, Result}) ->
            Expected = case Result of
                ok  -> ok;
                err -> {error, {version_mismatch, {RabbitVersion, Versions}}}
            end,
            {Expected, RabbitVersion, Versions} =
                {rabbit_plugins:version_support(RabbitVersion, Versions),
                 RabbitVersion, Versions}
        end,
        Examples),
    passed.

-record(validation_example, {rabbit_version, plugins, errors, valid}).

test_plugin_validation() ->
    Examples = [
        #validation_example{
         rabbit_version = "3.7.1",
         plugins =
          [{plugin_a, "3.7.2", ["3.5.6", "3.7.1"], []},
           {plugin_b, "3.7.2", ["3.7.0"], [{plugin_a, ["3.6.3", "3.7.1"]}]}],
         errors = [],
         valid = [plugin_a, plugin_b]},

        #validation_example{
         rabbit_version = "3.7.1",
         plugins =
          [{plugin_a, "3.7.1", ["3.7.6"], []},
           {plugin_b, "3.7.2", ["3.7.0"], [{plugin_a, ["3.6.3", "3.7.0"]}]}],
         errors =
          [{plugin_a, [{version_mismatch, {"3.7.1", ["3.7.6"]}}]},
           {plugin_b, [{missing_dependency, plugin_a}]}],
         valid = []
        },

        #validation_example{
         rabbit_version = "3.7.1",
         plugins =
          [{plugin_a, "3.7.1", ["3.7.6"], []},
           {plugin_b, "3.7.2", ["3.7.0"], [{plugin_a, ["3.7.0"]}]},
           {plugin_c, "3.7.2", ["3.7.0"], [{plugin_b, ["3.7.3"]}]}],
         errors =
          [{plugin_a, [{version_mismatch, {"3.7.1", ["3.7.6"]}}]},
           {plugin_b, [{missing_dependency, plugin_a}]},
           {plugin_c, [{missing_dependency, plugin_b}]}],
         valid = []
        },

        #validation_example{
         rabbit_version = "3.7.1",
         plugins =
          [{plugin_a, "3.7.1", ["3.7.1"], []},
           {plugin_b, "3.7.2", ["3.7.0"], [{plugin_a, ["3.7.3"]}]},
           {plugin_d, "3.7.2", ["3.7.0"], [{plugin_c, ["3.7.3"]}]}],
         errors =
          [{plugin_b, [{{version_mismatch, {"3.7.1", ["3.7.3"]}}, plugin_a}]},
           {plugin_d, [{missing_dependency, plugin_c}]}],
         valid = [plugin_a]
        }],
    lists:foreach(
        fun(#validation_example{rabbit_version = RabbitVersion,
                                plugins = PluginsExamples,
                                errors  = Errors,
                                valid   = ExpectedValid}) ->
            Plugins = make_plugins(PluginsExamples),
            {Valid, Invalid} = rabbit_plugins:validate_plugins(Plugins,
                                                               RabbitVersion),
            Errors = lists:reverse(Invalid),
            ExpectedValid = lists:reverse(lists:map(fun(#plugin{name = Name}) ->
                                                        Name
                                                    end,
                                                    Valid))
        end,
        Examples),
    passed.

make_plugins(Plugins) ->
    lists:map(
        fun({Name, Version, RabbitVersions, PluginsVersions}) ->
            Deps = [K || {K,_V} <- PluginsVersions],
            #plugin{name = Name,
                    version = Version,
                    dependencies = Deps,
                    rabbitmq_versions = RabbitVersions,
                    plugins_versions = PluginsVersions}
        end,
        Plugins).