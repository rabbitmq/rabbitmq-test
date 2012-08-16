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
-module(dynamic_ha_cluster_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-define(VHOST, <<"/">>).

-export([suite/0, all/0, init_per_suite/1,
         end_per_suite/1,
         simple_test/0,
         simple_test/1]).

%% NB: it can take almost a minute to start and cluster 3 nodes,
%% and then we need time left over to run the actual tests...
suite() -> [{timetrap, systest:settings("time_traps.ha_cluster_SUITE")}].

all() ->
    systest_suite:export_all(?MODULE).

init_per_suite(Config) ->
    timer:start(),
    Config.

end_per_suite(_Config) ->
    ok.

simple_test() ->
    [].
    %% NB: up to 1.5 mins to fully cluster the nodes
    %%[{timetrap, systest:settings("time_traps.restarted_master")}].

simple_test(Config) ->
    {_Cluster, [{{A, _ARef}, {_AConn, ACh}},
                {{B, _BRef}, {_BConn, _BCh}},
                {{C, _CRef}, {_CConn, _CCh}}]} =
        rabbit_ha_test_utils:cluster_members(Config),

    Q = <<"ha.test">>,
    %% When we first declare a queue with no policy, it's not HA.
    #'queue.declare_ok'{} = amqp_channel:call(ACh, #'queue.declare'{queue = Q}),
    assert_slaves(A, Q, A, ''),

    %% Give it policy "all", it becomes HA and gets all mirrors
    set_policy(A, Q, <<"all">>, []),
    assert_slaves(A, Q, A, [B, C]),

    %% Give it policy "nodes", it gets specific mirrors
    set_policy(A, Q, <<"nodes">>, [a2b(A), a2b(B)]),
    assert_slaves(A, Q, A, [B]),

    ok.

%%----------------------------------------------------------------------------

assert_slaves(RPCNode, QName, ExpMNode, ExpSNodes) ->
    Qs = rpc:call(RPCNode, rabbit_amqqueue, info_all, [?VHOST], infinity),
    Q = find_queue(QName, Qs),
    Pid = proplists:get_value(pid, Q),
    SPids = proplists:get_value(slave_pids, Q),
    ActMNode = node(Pid),
    ActSNodes = case SPids of
                    '' -> '';
                    _  -> [node(SPid) || SPid <- SPids]
                end,
    case ExpMNode =:= ActMNode andalso equal_list(ExpSNodes, ActSNodes) of
        false ->
            %% It's an async change, so if nothing has changed let's
            %% just wait - of course this means if something does not
            %% change when expected then we time out the test which is
            %% a bit tedious
            case get(previous_exp_m_node) =:= ActMNode andalso
                equal_list(get(previous_exp_s_nodes), ActSNodes) of
                true  -> timer:sleep(100),
                         assert_slaves(RPCNode, QName, ExpMNode, ExpSNodes);
                false -> ct:fail("Expected ~p / ~p, got ~p / ~p~n",
                                 [ExpMNode, ExpSNodes, ActMNode, ActSNodes])
            end;
        true ->
            put(previous_exp_m_node, ExpMNode),
            put(previous_exp_s_nodes, ExpSNodes),
            ok
    end.

equal_list('',    '')   -> true;
equal_list('',    _Act) -> false;
equal_list(_Exp,  '')   -> false;
equal_list([],    [])   -> true;
equal_list(_Exp,  [])   -> false;
equal_list([],    _Act) -> false;
equal_list([H|T], Act)  -> case lists:member(H, Act) of
                               true  -> equal_list(T, Act -- [H]);
                               false -> false
                           end.

find_queue(QName, Qs) ->
    case [Q || Q <- Qs, proplists:get_value(name, Q) =:=
                   rabbit_misc:r(?VHOST, queue, QName)] of
        [R] -> R;
        []  -> exit({did_not_find_queue, QName})
    end.

%%----------------------------------------------------------------------------

set_policy(RPCNode, QName, HAMode, HAParams) ->
    %% TODO vhost will go here after bug25071 merged
    rpc:call(RPCNode, rabbit_runtime_parameters, set,
             [<<"policy">>, <<"HA">>,
              [{<<"prefix">>, QName},
               {<<"policy">>, [{<<"ha-mode">>,   HAMode},
                               {<<"ha-params">>, HAParams}
                              ]}
              ]
             ]).

a2b(A) -> list_to_binary(atom_to_list(A)).
