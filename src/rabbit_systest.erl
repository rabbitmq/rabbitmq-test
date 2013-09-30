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
%% Copyright (c) 2007-2013 GoPivotal, Inc.  All rights reserved.
%%
-module(rabbit_systest).

-export([profile_test/2, cover_dirs/1, package_test/2]).

profile_test(Profile, Opts) ->
    prepare(),
    systest_runner:execute([{profile, Profile}|Opts] ++ verbosity()).

cover_dirs(Base) ->
    case file:list_dir(Base) of
        {ok, Dirs} ->
            [{'cover-dir', D} || D <- absolutify(Base, Dirs),
                                 filelib:is_dir(D)];
        _ ->
            []
    end.

absolutify(Base, Dirs) ->
    [filename:absname(filename:join([Base, D, "ebin"])) || D <- Dirs].

package_test(TestSuite, Opts) ->
    prepare(),
    systest_runner:execute([{testsuite, TestSuite}|Opts] ++ verbosity()).

verbosity() ->
    case os:getenv("SYSTEST_VERBOSE") of
        false -> [];
        _     -> [{logging, "process"},
                  {logging, "sut"},
                  {logging, "framework"}]
    end.

prepare() ->
    application:load(systest),
    {ok, Cwd} = file:get_cwd(),
    os:putenv("PACKAGE_DIR", Cwd),
    os:putenv("RABBITMQ_BROKER_DIR",
              filename:absname(filename:join([Cwd, "..", "rabbitmq-server"]))).
