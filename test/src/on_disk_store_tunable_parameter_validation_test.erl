%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License at
%% http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%% License for the specific language governing rights and limitations
%% under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2011-2015 Pivotal Software, Inc.  All rights reserved.
%%

-module(on_disk_store_tunable_parameter_validation_test).

-include("rabbit.hrl").

-export([test_msg_store_parameter_validation/0]).

-define(T(Fun, Args), (catch apply(rabbit, Fun, Args))).

test_msg_store_parameter_validation() ->
    %% make sure it works with default values
    ok = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [?CREDIT_DISC_BOUND, ?IO_BATCH_SIZE]),

    %% IO_BATCH_SIZE must be greater than CREDIT_DISC_BOUND initial credit
    ok = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [{2000, 500}, 3000]),
    {error, _} = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [{2000, 500}, 1500]),

    %% All values must be integers
    {error, _} = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [{2000, 500}, "1500"]),
    {error, _} = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [{"2000", 500}, abc]),
    {error, _} = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [{2000, "500"}, 2048]),

    %% CREDIT_DISC_BOUND must be a tuple
    {error, _} = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [[2000, 500], 1500]),
    {error, _} = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [2000, 1500]),

    %% config values can't be smaller than default values
    {error, _} = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [{1999, 500}, 2048]),
    {error, _} = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [{2000, 499}, 2048]),
    {error, _} = ?T(validate_msg_store_io_batch_size_and_credit_disc_bound, [{2000, 500}, 2047]),

    passed.
