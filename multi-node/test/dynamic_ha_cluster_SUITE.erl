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

%% rabbit_tests:test_dynamic_mirroring() is a unit test which should
%% test the logic of what all the policies decide to do, so we don't
%% need to exhaustively test that here. What we need to test is that:
%%
%% * Going from non-mirrored to mirrored works and vice versa
%% * Changing policy can add / remove mirrors and change the master
%% * Adding a node will create a new mirror when there are not enough nodes
%%   for the policy
%% * Removing a node will create a new mirror when there are more than enough
%%   nodes for the policy
%%
%% The first two are change_policy_test, the last two are change_cluster_test

-include_lib("common_test/include/ct.hrl").
-include_lib("systest/include/systest.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").

-define(QNAME, <<"ha.test">>).
-define(POLICY, <<"^ha.test$">>). %% " emacs
-define(VHOST, <<"/">>).

-export([suite/0, all/0, init_per_suite/1, end_per_suite/1,
         change_policy_test/1,
         change_cluster_test/1]).

-import(rabbit_ha_test_utils, [set_policy/4, clear_policy/2, a2b/1]).

%% NB: it can take almost a minute to start and cluster 3 nodes,
%% and then we need time left over to run the actual tests...
suite() -> [{timetrap, systest:settings("time_traps.ha_cluster_SUITE")}].

all() ->
    systest_suite:export_all(?MODULE).

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

change_policy_test(Config) ->
    %% TODO this test only needs three nodes
    SUT = systest:active_sut(Config),
    [{A, ARef},
     {B, _BRef},
     {C, _CRef},
     {_D, _DRef},
     {_E, _ERef}] = systest:list_processes(SUT),
    ACh = ?REQUIRE(amqp_channel, systest:read_process_user_data(ARef)),

    %% When we first declare a queue with no policy, it's not HA.
    amqp_channel:call(ACh, #'queue.declare'{queue = ?QNAME}),
    assert_slaves(A, ?QNAME, {A, ''}),

    %% Give it policy "all", it becomes HA and gets all mirrors
    set_policy(A, ?POLICY, <<"all">>, []),
    assert_slaves(A, ?QNAME, {A, [B, C]}),

    %% Give it policy "nodes", it gets specific mirrors
    set_policy(A, ?POLICY, <<"nodes">>, [a2b(A), a2b(B)]),
    assert_slaves(A, ?QNAME, {A, [B]}),

    %% Now explicitly change the mirrors and the master
    set_policy(A, ?POLICY, <<"nodes">>, [a2b(B), a2b(C)]),
    assert_slaves(A, ?QNAME, {B, [C]}), %% B becomes master; it's older

    %% Clear the policy, and we go back to non-mirrored
    clear_policy(A, ?POLICY),
    assert_slaves(A, ?QNAME, {B, ''}),

    %% Test switching away from an unmirrored node
    set_policy(A, ?POLICY, <<"nodes">>, [a2b(A), a2b(C)]),
    assert_slaves(A, ?QNAME, {C, [A]}),

    ok.

change_cluster_test(Config) ->
    %% ABC are clustered at start; DE are not started
    SUT = systest:active_sut(Config),
    [{A, ARef},
     {B, _BRef},
     {C, _CRef},
     {D, DRef},
     {E, ERef}] = systest:list_processes(SUT),
    ACh = ?REQUIRE(amqp_channel, systest:read_process_user_data(ARef)),

    amqp_channel:call(ACh, #'queue.declare'{queue = ?QNAME}),
    assert_slaves(A, ?QNAME, {A, ''}),

    %% Give it policy exactly 4, it should mirror to all 3 nodes
    set_policy(A, ?POLICY, <<"exactly">>, 4),
    assert_slaves(A, ?QNAME, {A, [B, C]}),

    %% Add D and E, D joins in
    ok = systest:activate_process(DRef),
    ok = systest:activate_process(ERef),
    rabbit_ha_test_utils:cluster(D, A),
    rabbit_ha_test_utils:cluster(E, A),
    assert_slaves(A, ?QNAME, {A, [B, C, D]}),

    %% Remove D, E joins in
    systest:stop_and_wait(DRef),
    assert_slaves(A, ?QNAME, {A, [B, C, E]}, [{A, [B, C]}]),

    ok.

%%----------------------------------------------------------------------------

assert_slaves(RPCNode, QName, Exp) ->
    assert_slaves(RPCNode, QName, Exp, []).

assert_slaves(RPCNode, QName, Exp, PermittedIntermediate) ->
    assert_slaves0(RPCNode, QName, Exp,
                  [{get(previous_exp_m_node), get(previous_exp_s_nodes)} |
                   PermittedIntermediate]).

assert_slaves0(RPCNode, QName, {ExpMNode, ExpSNodes}, PermittedIntermediate) ->
    Q = find_queue(QName, RPCNode),
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
            case [found || {PermMNode, PermSNodes} <- PermittedIntermediate,
                           PermMNode =:= ActMNode,
                           equal_list(PermSNodes, ActSNodes)] of
                [] -> ct:fail("Expected ~p / ~p, got ~p / ~p~nat ~p~n",
                              [ExpMNode, ExpSNodes, ActMNode, ActSNodes,
                               get_stacktrace()]);
                _  -> timer:sleep(100),
                      assert_slaves0(RPCNode, QName, {ExpMNode, ExpSNodes},
                                     PermittedIntermediate)
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

find_queue(QName, RPCNode) ->
    Qs = rpc:call(RPCNode, rabbit_amqqueue, info_all, [?VHOST], infinity),
    case find_queue0(QName, Qs) of
        did_not_find_queue -> timer:sleep(100),
                              find_queue(QName, RPCNode);
        Q -> Q
    end.

find_queue0(QName, Qs) ->
    case [Q || Q <- Qs, proplists:get_value(name, Q) =:=
                   rabbit_misc:r(?VHOST, queue, QName)] of
        [R] -> R;
        []  -> did_not_find_queue
    end.

get_stacktrace() ->
    try
        throw(e)
    catch
        _:e ->
            erlang:get_stacktrace()
    end.
