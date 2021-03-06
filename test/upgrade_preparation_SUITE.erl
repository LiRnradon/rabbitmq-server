%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at https://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2020 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(upgrade_preparation_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

all() ->
    [
      {group, clustered}
    ].

groups() ->
    [
     {clustered, [], [
         await_quorum_plus_one
     ]}
    ].


%% -------------------------------------------------------------------
%% Test Case
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    rabbit_ct_helpers:run_setup_steps(Config).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config).

init_per_group(Group, Config) ->
    Config1 = rabbit_ct_helpers:set_config(Config, [
        {rmq_nodes_count, 3},
        {rmq_nodename_suffix, Group}
      ]),
    rabbit_ct_helpers:run_steps(Config1,
      rabbit_ct_broker_helpers:setup_steps() ++
      rabbit_ct_client_helpers:setup_steps()).

end_per_group(_Group, Config) ->
    rabbit_ct_helpers:run_steps(Config,
              rabbit_ct_client_helpers:teardown_steps() ++
              rabbit_ct_broker_helpers:teardown_steps()).


init_per_testcase(TestCase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, TestCase),
    case rabbit_ct_broker_helpers:enable_feature_flag(Config, quorum_queue) of
        ok   -> Config;
        Skip -> Skip
    end.

end_per_testcase(TestCase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, TestCase).



%%
%% Test Cases
%%

-define(WAITING_INTERVAL, 10000).

await_quorum_plus_one(Config) ->
    catch delete_queues(),
    [A, B, _C] = rabbit_ct_broker_helpers:get_node_configs(Config, nodename),
    Ch = rabbit_ct_client_helpers:open_channel(Config, A),
    declare(Ch, <<"qq.1">>, [{<<"x-queue-type">>, longstr, <<"quorum">>}]),
    timer:sleep(100),
    ?assert(await_quorum_plus_one(Config, 0)),

    ok = rabbit_ct_broker_helpers:stop_node(Config, B),
    ?assertNot(await_quorum_plus_one(Config, 0)),

    ok = rabbit_ct_broker_helpers:start_node(Config, B),
    ?assert(await_quorum_plus_one(Config, 0)).

%%
%% Implementation
%%

declare(Ch, Q) ->
    declare(Ch, Q, []).

declare(Ch, Q, Args) ->
    amqp_channel:call(Ch, #'queue.declare'{queue     = Q,
                                           durable   = true,
                                           auto_delete = false,
                                           arguments = Args}).

delete_queues() ->
    [rabbit_amqqueue:delete(Q, false, false, <<"tests">>) || Q <- rabbit_amqqueue:list()].

await_quorum_plus_one(Config, Node) ->
    await_quorum_plus_one(Config, Node, ?WAITING_INTERVAL).

await_quorum_plus_one(Config, Node, Timeout) ->
    rabbit_ct_broker_helpers:rpc(Config, Node,
        rabbit_upgrade_preparation, await_online_quorum_plus_one, [Timeout], Timeout + 500).

