%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 2026. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

%% Standalone probe for known-float ordered comparisons. check/0 covers
%% comparison semantics; run_kernel/3 accepts preallocated float pairs so the
%% comparison cost can be measured without creating floats in the timed loop.
%%
%% The kernel variants are selected as
%%   run_kernel({compare, typed_lt_first}, Pairs, Iterations)
%%   run_kernel({compare, typed_gt_first}, Pairs, Iterations)
%%   run_kernel({compare, untyped_lt_first}, Pairs, Iterations)
%%   run_kernel({compare, untyped_gt_first}, Pairs, Iterations)
%% and return {Checksum, Iterations}.
%%
%% Compile once with `erlc -o build typed_float_compare_bench.erl`, then run
%% the same `build/typed_float_compare_bench.beam` in fresh VMs started from
%% each preserved emulator path. In each VM, after loading the module:
%%
%%   Pairs = [{float(I), float(I + 0.5)} || I <- lists:seq(1, 32)],
%%   {-1, 1} = typed_float_compare_bench:run_kernel(
%%               {compare, typed_lt_first}, Pairs, 1),
%%   {Micros, {-100000, 100000}} =
%%       timer:tc(fun() ->
%%                        typed_float_compare_bench:run_kernel(
%%                          {compare, typed_lt_first}, Pairs, 100000)
%%                end),
%%   io:format("~p microseconds~n", [Micros]).

-module(typed_float_compare_bench).

-export([check/0, float_lt_first/2, float_gt_first/2, run_kernel/3]).

float_lt_first(A, B) when is_float(A), is_float(B) ->
    if
        A < B -> lt;
        A > B -> gt;
        true -> eq
    end.

float_gt_first(A, B) when is_float(A), is_float(B) ->
    if
        A > B -> gt;
        A < B -> lt;
        true -> eq
    end.

untyped_lt_first(A, B) ->
    if
        A < B -> lt;
        A > B -> gt;
        true -> eq
    end.

untyped_gt_first(A, B) ->
    if
        A > B -> gt;
        A < B -> lt;
        true -> eq
    end.

check() ->
    Max = 1.7976931348623157e308,
    Min = -Max,
    Tiny = 5.0e-324,
    Same = 23.5,
    Independent = binary_to_term(term_to_binary(Same)),
    false = erts_debug:same(Same, Independent),
    eq = float_lt_first(Same, Same),
    eq = float_gt_first(Independent, Same),
    eq = float_lt_first(-0.0, 0.0),
    eq = float_gt_first(0.0, -0.0),
    lt = float_lt_first(Min, Tiny),
    gt = float_lt_first(Max, Min),
    lt = float_gt_first(Tiny, Max),
    eq = float_lt_first(Max, Max),
    Pairs = [{float(I rem 7), float((I + 1) rem 7)} || I <- lists:seq(0, 31)],
    Expected = {-48, 64},
    {Checksum, Iterations} = run_kernel({compare, typed_lt_first},
                                        Pairs, 64),
    Expected = {Checksum, Iterations},
    Expected = run_kernel({compare, typed_gt_first}, Pairs, 64),
    Expected = run_kernel({compare, untyped_lt_first}, Pairs, 64),
    Expected = run_kernel({compare, untyped_gt_first}, Pairs, 64),
    ok.

run_kernel({compare, Order}, Pairs, N)
  when is_list(Pairs), Pairs =/= [], is_integer(N), N >= 0 ->
    {Checksum, 0} = kernel(N, Pairs, Pairs, Order, 0),
    {Checksum, N}.

kernel(0, _Remaining, _Pairs, _Order, Checksum) ->
    {Checksum, 0};
kernel(N, [], Pairs, Order, Checksum) ->
    kernel(N, Pairs, Pairs, Order, Checksum);
kernel(N, [{A, B} | Remaining], Pairs, Order, Checksum) ->
    Result = compare(Order, A, B),
    kernel(N - 1, Remaining, Pairs, Order, Checksum + result_code(Result)).

compare(typed_lt_first, A, B) -> float_lt_first(A, B);
compare(typed_gt_first, A, B) -> float_gt_first(A, B);
compare(untyped_lt_first, A, B) -> untyped_lt_first(A, B);
compare(untyped_gt_first, A, B) -> untyped_gt_first(A, B).

result_code(lt) -> -1;
result_code(eq) -> 0;
result_code(gt) -> 1.
