-module(rabbit_plugins_tests).

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
