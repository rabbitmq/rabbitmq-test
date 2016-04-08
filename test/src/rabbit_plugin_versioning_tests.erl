-module(rabbit_plugin_versioning_tests).
-include("rabbit.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

version_support_test() ->
    Examples = [
     {[], "any version", true} %% anything goes
    ,{[], "0.0.0", true}       %% ditto
    ,{[], "3.5.6", true}       %% ditto
    ,{["something"], "something", true}            %% equal values match
    ,{["3.5.4"], "something", false}
    ,{["3.4.5", "3.6.0"], "0.0.0", true}           %% zero version always match
    ,{["3.4.5", "3.6.0"], "", true}                %% empty version always match
    ,{["something", "3.5.6"], "3.5.7", true}       %% 3.5.7 matches ~> 3.5.6
    ,{["3.4.0", "3.5.6"], "3.6.1", false}          %% 3.6.x isn't supported
    ,{["3.5.2", "3.6.1", "3.7.1"], "3.5.2", true}  %% 3.5.2 matches ~> 3.5.2
    ,{["3.5.2", "3.6.1", "3.7.1"], "3.5.1", false} %% lesser than the lower boundary
    ,{["3.5.2", "3.6.1", "3.7.1"], "3.6.2", true}  %% 3.6.2 matches ~> 3.6.1
    ,{["3.5", "3.6", "3.7"], "3.5.1", false}       %% x.y values are not supported
    ,{["3"], "3.5.1", false}                       %% x values are not supported
    ],

    lists:foreach(
        fun({Versions, RabbitVersion, Expected}) ->
            {Expected, RabbitVersion, Versions} =
                {rabbit_plugins:is_version_supported(RabbitVersion, Versions),
                 RabbitVersion, Versions}
        end,
        Examples),
    ok.

-record(validation_example, {rabbit_version, plugins, errors, valid}).

plugin_validation_test() ->
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
          [{plugin_a, [{broker_version_mismatch, "3.7.1", ["3.7.6"]}]},
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
          [{plugin_a, [{broker_version_mismatch, "3.7.1", ["3.7.6"]}]},
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
          [{plugin_b, [{{dependency_version_mismatch, "3.7.1", ["3.7.3"]}, plugin_a}]},
           {plugin_d, [{missing_dependency, plugin_c}]}],
         valid = [plugin_a]
        },
        #validation_example{
         rabbit_version = "0.0.0",
         plugins =
          [{plugin_a, "", ["3.7.1"], []},
           {plugin_b, "3.7.2", ["3.7.0"], [{plugin_a, ["3.7.3"]}]}],
         errors = [],
         valid  = [plugin_a, plugin_b]
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
    ok.

make_plugins(Plugins) ->
    lists:map(
        fun({Name, Version, RabbitVersions, PluginsVersions}) ->
            Deps = [K || {K,_V} <- PluginsVersions],
            #plugin{name = Name,
                    version = Version,
                    dependencies = Deps,
                    broker_version_requirements = RabbitVersions,
                    dependency_version_requirements = PluginsVersions}
        end,
        Plugins).
