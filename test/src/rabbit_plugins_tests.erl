-module(rabbit_plugins_tests).

-compile(export_all).

test_version_support() ->
    Examples = [
     {[], "any version", ok} % any version
    ,{[], "0.0.0", ok}       % any version
    ,{[], "3.5.6", ok}       % any version
    ,{["something"], "something", ok}      % Equal always match 
    ,{["3.5.4"], "something", err}
    ,{["something", "3.5.6"], "3.5.7", ok} % any version can match
    ,{["3.4.0", "3.5.6"], "3.6.1", err}    % major version should present
    ,{["3.5.2", "3.6.1"], "3.5.2", ok}     % equal version match
    ,{["3.5.2", "3.6.1"], "3.5.1", err}    % lesser version don't match
    ,{["3.5.2", "3.6.1"], "3.6.2", ok}     % greated version match
    ,{["3.5.2", "3.6.1"], "0.0.0", err}    % default version don't match!
    ,{["3.5", "3.6"], "3.5.1", err}        % Shorter version not supported
    ,{["3"], "3.5.1", err}                 
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
