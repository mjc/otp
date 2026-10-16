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

%% Standalone comparison-mechanism benchmark. Compile this source with each
%% compiler being compared; use distinct module and tree-module names:
%%
%%   compile:file(File, [binary,
%%                       {d, 'BENCH_MODULE', ordering_bench_base},
%%                       {d, 'TREE_MODULE', gb_trees_base}])
%%   compile:file(File, [binary,
%%                       {d, 'BENCH_MODULE', ordering_bench_candidate},
%%                       {d, 'TREE_MODULE', gb_trees_candidate}])
%%
%% Save each returned binary as <module>.beam, and compile/rename gb_trees
%% under that compiler by parsing lib/stdlib/src/gb_trees.erl with epp, changing
%% only `{attribute, Line, module, gb_trees}` to the chosen tree-module atom,
%% and passing the forms to compile:forms/2 with `[binary]` (there are no
%% executable self-calls). For a baseline/baseline control, compile two
%% distinct benchmark modules and two distinct tree modules with the same
%% baseline compiler, then pass both benchmark names as baseline_module and
%% candidate_module. Load all modules into one fresh runtime. Repeat in another
%% fresh runtime with module load order reversed and record it with
%% `load_order => baseline_first` or `candidate_first`. The option
%% `variant_order => candidate_first` reverses the default alternating AB/BA
%% warmup and measurement schedule; it does not hold every round in one order.
%% Use a quiet dedicated VM because GC deltas are VM-global counters. Output
%% includes resolved options, runtime details, object-code hashes, and source
%% hashes when source files are available. A fixed seed shuffles cases and
%% each tree query sequence.
%%
%% Example from the driver module:
%%   ordering_bench_base:run(#{baseline_module => ordering_bench_base,
%%                             candidate_module => ordering_bench_candidate,
%%                             mode => smoke,
%%                             load_order => baseline_first})
%%
%% Output is CSV on standard output. Inputs and setup oracles are prepared
%% before timing. Each timed batch is one external call into a local recursive
%% loop, with the ordered comparison ladder executed for every input.

-ifndef(BENCH_MODULE).
-define(BENCH_MODULE, ordering_comparison_bench).
-endif.
-ifndef(TREE_MODULE).
-define(TREE_MODULE, gb_trees).
-endif.

-module(?BENCH_MODULE).

-export([run/1, run_kernel/3, info/0]).

-define(FLATMAP_KEYS, 16).
-define(HAMT_KEYS, 64).

run(Options0) ->
    Options = options(Options0),
    Base = maps:get(baseline_module, Options),
    Candidate = maps:get(candidate_module, Options),
    ok = ensure_module(Base),
    ok = ensure_module(Candidate),
    Specs = shuffle(case_specs(maps:get(mode, Options), maps:get(size, Options)),
                    maps:get(seed, Options)),
    emit_metadata(Options, Base, Candidate),
    io:put_chars("case,order,round,variant,N,ns,checksum,gc_delta\n"),
    run_cases(Specs, Base, Candidate, Options, 0),
    ok.

options(Options) when is_map(Options) ->
    defaults(Options);
options(Options) when is_list(Options) ->
    defaults(maps:from_list(Options)).

defaults(Options) ->
    Mode = maps:get(mode, Options, smoke),
    true = (Mode =:= smoke orelse Mode =:= full),
    Size0 = maps:get(size, Options, case Mode of smoke -> 8; full -> 64 end),
    Size = max(4, Size0),
    Rounds0 = maps:get(rounds, Options, case Mode of smoke -> 2; full -> 8 end),
    Rounds = max(1, Rounds0),
    MaxIterations0 = maps:get(max_iterations, Options,
                              case Mode of smoke -> 128; full -> 5000000 end),
    MaxIterations = max(1, MaxIterations0),
    TargetMs0 = maps:get(target_ms, Options, case Mode of smoke -> 1; full -> 14 end),
    TargetMs = max(1, TargetMs0),
    PilotMinMs0 = maps:get(pilot_min_ms, Options,
                           case Mode of smoke -> 1; full -> 8 end),
    PilotMinMs = max(1, PilotMinMs0),
    PilotMaxMs0 = maps:get(pilot_max_ms, Options,
                           case Mode of smoke -> 2; full -> 30 end),
    PilotMaxMs = max(PilotMinMs, PilotMaxMs0),
    PilotMaxIterations = max(1, maps:get(pilot_max_iterations, Options, 1000000)),
    VariantOrder = maps:get(variant_order, Options, balanced),
    true = lists:member(VariantOrder, [balanced, candidate_first]),
    LoadOrder = maps:get(load_order, Options, not_recorded),
    true = lists:member(LoadOrder, [baseline_first, candidate_first, not_recorded]),
    #{baseline_module => maps:get(baseline_module, Options, ?MODULE),
      candidate_module => maps:get(candidate_module, Options, ?MODULE),
      mode => Mode,
      rounds => Rounds,
      size => Size,
      target_ms => TargetMs,
      max_iterations => MaxIterations,
      pilot_min_ms => PilotMinMs,
      pilot_max_ms => PilotMaxMs,
      pilot_max_iterations => PilotMaxIterations,
      seed => maps:get(seed, Options, 20261016),
      load_order => LoadOrder,
      provenance => maps:get(provenance, Options, unspecified),
      variant_order => VariantOrder}.

info() ->
    #{module => ?MODULE, tree_module => ?TREE_MODULE}.

emit_metadata(Options, Base, Candidate) ->
    io:format("# runtime_otp_release=~s~n", [erlang:system_info(otp_release)]),
    io:format("# runtime_version=~s~n", [erlang:system_info(system_version)]),
    io:format("# runtime_arch=~s~n", [erlang:system_info(system_architecture)]),
    io:format("# runtime_emulator=~p~n", [erlang:system_info(emu_flavor)]),
    io:format("# options=~tw~n", [Options]),
    io:format("# gc_delta_scope=vm_global; use_a_quiet_dedicated_vm=true~n", []),
    lists:foreach(fun(Module) -> emit_module_metadata(Module, Options) end,
                  [Base, Candidate]),
    ok.

emit_module_metadata(Module, Options) ->
    #{tree_module := TreeModule} = Module:info(),
    SourcePath = source_path(Module),
    SourceHash = file_hash(SourcePath),
    io:format("# benchmark_module=~p tree_module=~p module_md5=~s "
              "tree_module_md5=~s source=~ts source_md5=~s "
              "load_order=~p provenance=~tw~n",
              [Module, TreeModule, object_hash(Module), object_hash(TreeModule),
               SourcePath, SourceHash, maps:get(load_order, Options),
               maps:get(provenance, Options)]).

source_path(Module) ->
    case proplists:get_value(source, Module:module_info(compile)) of
        Path when is_list(Path) -> Path;
        _ -> "unavailable"
    end.

file_hash("unavailable") -> "unavailable";
file_hash(Path) ->
    case file:read_file(Path) of
        {ok, Binary} -> hex(erlang:md5(Binary));
        _ -> "unavailable"
    end.

object_hash(Module) ->
    try hex(Module:module_info(md5))
    catch _:_ -> "unavailable"
    end.

hex(Binary) -> binary_to_list(binary:encode_hex(Binary)).

ensure_module(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} -> ok;
        Error -> erlang:error({module_not_loaded, Module, Error})
    end.

case_specs(smoke, _Size) ->
    [{scalar, small, lt, lt_first},
     {scalar, small, eq, gt_first},
     {complex, list, copied_eq, lt_first},
     {complex, list, late_lt, gt_first},
     {complex, flatmap, late_gt, lt_first},
     {complex, bits, copied_eq, gt_first},
     {tree, hit, integer},
     {tree, miss, integer},
     {tree, update, integer},
     {mixed, mixed_stream, lt_first},
     {mixed, mixed_stream, gt_first}];
case_specs(full, _Size) ->
    Orders = [lt_first, gt_first],
    Scalars = [{scalar, Type, Relation, Order}
               || Type <- [small, mixed, float, atoms],
                  Relation <- [lt, eq, gt],
                  Order <- Orders],
    Terms = [{complex, Type, Work, Order}
             || Type <- [list, tuple, flatmap, binary, bits],
                Work <- [shared_eq, copied_eq, early_lt, late_lt,
                         early_gt, late_gt],
                Order <- Orders],
    Hamt = [{complex, hamt, Work, Order}
            || Work <- [shared_eq, copied_eq], Order <- Orders],
    Mixed = [{mixed, mixed_stream, Order} || Order <- Orders],
    Trees = [{tree, Action, KeyType}
             || Action <- [hit, miss, update],
                KeyType <- [integer, prefix16, prefix256]],
    Scalars ++ Terms ++ Hamt ++ Mixed ++ Trees.

run_cases([], _Base, _Candidate, _Options, _Index) ->
    ok;
run_cases([Spec | Rest], Base, Candidate, Options, Index) ->
    Case = prepare_case(Spec, maps:get(size, Options), maps:get(seed, Options)),
    Inputs = maps:get(inputs, Case),
    Kernel = maps:get(kernel, Case),
    validate_setup(Case, Base, Candidate),
    {WarmFirst, WarmSecond} = variant_order(maps:get(variant_order, Options),
                                            1, Index, Base, Candidate),
    N = choose_iterations(Base, Candidate, Kernel, Inputs,
                          maps:get(target_ms, Options),
                          maps:get(max_iterations, Options), Options),
    warm(WarmFirst, Kernel, Inputs, N),
    warm(WarmSecond, Kernel, Inputs, N),
    run_rounds(Case, Base, Candidate, Options, N, 1, Index),
    run_cases(Rest, Base, Candidate, Options, Index + 1).

prepare_case({scalar, Type, Relation, Order}, Size, Seed) ->
    Pairs = scalar_pairs(Type, Relation, vector_length(Size, Seed)),
    compare_case(case_name([Type, Relation]), Order, Relation, Pairs);
prepare_case({complex, Type, Work, Order}, Size, Seed) ->
    Pairs = complex_pairs(Type, Work, Size, vector_length(Size, Seed)),
    compare_case(case_name([Type, Work]), Order, relation_for_work(Work), Pairs);
prepare_case({mixed, mixed_stream, Order}, Size, Seed) ->
    Pairs = mixed_pairs(Size, vector_length(Size, Seed), Seed),
    compare_case("mixed_stream", Order, any, Pairs);
prepare_case({tree, Action, KeyType}, Size, Seed) ->
    tree_case(Action, KeyType, Size, Seed).

compare_case(Name, Order, Relation, Pairs) ->
    Codes = [oracle_code(A, B) || {A, B} <- Pairs],
    #{name => Name,
      order => Order,
      relation => Relation,
      kernel => {compare, Order},
      inputs => Pairs,
      expected_codes => Codes,
      expected_per_op => sum(Codes)}.

vector_length(Size, Seed) ->
    max(4, min(32, Size + (Seed band 3))).

scalar_pairs(Type, Relation, Count) ->
    [scalar_pair(Type, Relation, I) || I <- lists:seq(1, Count)].

scalar_pair(small, lt, I) -> {I, I + 1};
scalar_pair(small, eq, I) -> {I, I};
scalar_pair(small, gt, I) -> {I + 1, I};
scalar_pair(mixed, lt, I) -> {I, I + 0.5};
scalar_pair(mixed, eq, I) -> {I, float(I)};
scalar_pair(mixed, gt, I) -> {I + 1.0, I};
scalar_pair(float, lt, I) -> {float(I) + 0.25, float(I) + 0.5};
scalar_pair(float, eq, I) -> {float(I), float(I)};
scalar_pair(float, gt, I) -> {float(I) + 0.5, float(I) + 0.25};
scalar_pair(atoms, lt, _I) -> {alpha, beta};
scalar_pair(atoms, eq, _I) -> {alpha, alpha};
scalar_pair(atoms, gt, _I) -> {beta, alpha}.

complex_pairs(Type, Work, Size, Count) ->
    [complex_pair(Type, Work, Size, I) || I <- lists:seq(1, Count)].

complex_pair(Type, shared_eq, Size, _I) ->
    Term = base_term(Type, Size),
    {Term, Term};
complex_pair(Type, copied_eq, Size, _I) ->
    Term = base_term(Type, Size),
    {Term, copy_term(Term)};
complex_pair(Type, Work, Size, I) ->
    {Relation, Position} = work_relation(Work),
    make_ordered_pair(Type, Size, Relation, Position, I).

work_relation(early_lt) -> {lt, early};
work_relation(late_lt) -> {lt, late};
work_relation(early_gt) -> {gt, early};
work_relation(late_gt) -> {gt, late}.

relation_for_work(shared_eq) -> eq;
relation_for_work(copied_eq) -> eq;
relation_for_work(Work) -> element(1, work_relation(Work)).

make_ordered_pair(Type, Size, Relation, Position, I) ->
    Base = base_term(Type, Size),
    Index = case {Position, Type} of
                {early, bits} -> 0;
                {late, bits} -> bit_size(Base) - 1;
                {early, _} -> 1;
                {late, _} -> term_length(Type, Size)
            end,
    {LeftValue, RightValue} = case {Relation, I rem 2} of
                                  {lt, _} -> {0, 1};
                                  {gt, _} -> {1, 0}
                              end,
    Left = alter_term(Type, Base, Index, LeftValue),
    Right = alter_term(Type, Base, Index, RightValue),
    case Type of
        bits ->
            true = bit_size(Left) =:= bit_size(Base),
            true = bit_size(Right) =:= bit_size(Base);
        _ -> ok
    end,
    {Left, Right}.

term_length(flatmap, _Size) -> ?FLATMAP_KEYS;
term_length(hamt, _Size) -> ?HAMT_KEYS;
term_length(bits, Size) -> Size * 8 + 3;
term_length(_Type, Size) -> Size.

base_term(list, Size) -> lists:duplicate(Size, 0);
base_term(tuple, Size) -> list_to_tuple(lists:duplicate(Size, 0));
base_term(flatmap, _Size) -> value_map(?FLATMAP_KEYS);
base_term(hamt, _Size) -> value_map(?HAMT_KEYS);
base_term(binary, Size) -> list_to_binary(lists:duplicate(Size, 0));
base_term(bits, Size) ->
    list_to_bitstring([<<0:1>> || _ <- lists:seq(1, Size * 8 + 3)]).

value_map(Count) ->
    maps:from_list([{I, {0, I}} || I <- lists:seq(1, Count)]).

alter_term(list, List, Index, Value) -> replace_nth(List, Index, Value);
alter_term(tuple, Tuple, Index, Value) ->
    list_to_tuple(replace_nth(tuple_to_list(Tuple), Index, Value));
alter_term(flatmap, Map, Index, Value) -> alter_map_value(Map, Index, Value);
alter_term(hamt, Map, Index, Value) -> alter_map_value(Map, Index, Value);
alter_term(binary, Binary, Index, Value) ->
    Bytes = binary_to_list(Binary),
    list_to_binary(replace_nth(Bytes, Index, Value));
alter_term(bits, Bits, Index, Value) ->
    BitList = [Bit || <<Bit:1>> <= Bits],
    list_to_bitstring([<<Bit:1>> || Bit <- replace_nth(BitList, Index + 1, Value)]).

alter_map_value(Map, Key, Value) ->
    maps:update(Key, {Value, Key}, Map).

replace_nth([_ | Rest], 1, Value) -> [Value | Rest];
replace_nth([Head | Rest], Index, Value) when Index > 1 ->
    [Head | replace_nth(Rest, Index - 1, Value)].

copy_term(Term) when is_list(Term) -> [copy_term(Elem) || Elem <- Term];
copy_term(Term) when is_tuple(Term) ->
    list_to_tuple([copy_term(Elem) || Elem <- tuple_to_list(Term)]);
copy_term(Term) when is_map(Term) ->
    maps:from_list([{copy_term(Key), copy_term(Value)}
                    || {Key, Value} <- maps:to_list(Term)]);
copy_term(Term) when is_binary(Term) -> binary:copy(Term);
copy_term(Term) when is_bitstring(Term) ->
    list_to_bitstring([<<Bit:1>> || <<Bit:1>> <= Term]);
copy_term(Term) -> Term.

mixed_pairs(Size, Count, Seed) ->
    Pool = [scalar_pair(small, lt, Size),
            scalar_pair(mixed, eq, Size),
            scalar_pair(float, gt, Size),
            scalar_pair(atoms, lt, Size),
            complex_pair(list, late_lt, Size, 1),
            complex_pair(tuple, early_gt, Size, 2),
            complex_pair(flatmap, late_lt, Size, 3),
            complex_pair(binary, early_gt, Size, 4),
            complex_pair(bits, late_lt, Size, 5),
            complex_pair(hamt, copied_eq, Size, 6)],
    State0 = rand:seed_s(exsplus, {Seed + 11, Seed + 29, Seed + 47}),
    mixed_pairs(Count, Pool, State0, []).

mixed_pairs(0, _Pool, _State, Acc) -> lists:reverse(Acc);
mixed_pairs(Count, Pool, State0, Acc) ->
    {Index, State1} = rand:uniform_s(length(Pool), State0),
    mixed_pairs(Count - 1, Pool, State1, [lists:nth(Index, Pool) | Acc]).

tree_case(Action, KeyType, Size0, Seed) ->
    Size = max(8, min(512, Size0)),
    KeyPairs = tree_keys(KeyType, Size),
    Initial = [{Key, {original, Index}}
               || {Key, Index} <- KeyPairs],
    Tree = ?TREE_MODULE:from_orddict(Initial),
    Items0 = tree_items(Action, KeyPairs, Tree),
    Items = shuffle(Items0, Seed + action_seed(Action) + keytype_seed(KeyType)),
    ExpectedCodes = tree_codes(Action, Items),
    KeyIdentity = case {Action, KeyType} of
                      {update, integer} -> immediatekey;
                      {update, _} -> copied_first_pass_reused_key_steady_state;
                      {_, integer} -> immediatekey;
                      {_, _} -> copykey
                  end,
    #{name => case_name([gb_trees, Action, KeyType, KeyIdentity]),
      order => tree,
      kernel => {tree, Action},
      inputs => {Tree, Items},
      expected_codes => ExpectedCodes,
      expected_per_op => sum(ExpectedCodes),
      initial => Initial,
      key_pairs => KeyPairs}.

tree_keys(integer, Size) -> [{2 * I, I} || I <- lists:seq(1, Size)];
tree_keys(prefix16, Size) ->
    Prefix = lists:duplicate(16, 0),
    [{Prefix ++ [2 * I], I} || I <- lists:seq(1, Size)];
tree_keys(prefix256, Size) ->
    Prefix = lists:duplicate(256, 0),
    [{Prefix ++ [2 * I], I} || I <- lists:seq(1, Size)].

tree_items(hit, KeyPairs, _Tree) ->
    [{copy_key(Key), {value, {original, Index}}} || {Key, Index} <- KeyPairs];
tree_items(miss, KeyPairs, _Tree) ->
    [{copy_key(miss_key(Key)), none} || {Key, _Index} <- KeyPairs];
%% The first pass supplies an ETF-copied key. gb_trees:update/3 installs that
%% query key in the updated node, so later passes in the same timed batch reuse
%% it; update case names describe both phases.
tree_items(update, KeyPairs, _Tree) ->
    [{copy_key(Key), Index} || {Key, Index} <- KeyPairs].

copy_key(Key) when is_list(Key) -> binary_to_term(term_to_binary(Key));
copy_key(Key) -> Key.

action_seed(hit) -> 17;
action_seed(miss) -> 31;
action_seed(update) -> 47.

keytype_seed(integer) -> 101;
keytype_seed(prefix16) -> 211;
keytype_seed(prefix256) -> 307.

miss_key(Key) when is_integer(Key) -> Key + 1;
miss_key(Key) when is_list(Key) ->
    PrefixLength = length(Key) - 1,
    lists:sublist(Key, PrefixLength) ++ [lists:last(Key) + 1].

tree_codes(hit, Items) -> [value_checksum(Expected) || {_Key, Expected} <- Items];
tree_codes(miss, Items) -> [0 || {_Key, none} <- Items];
tree_codes(update, Items) -> [1 || {_Key, _Index} <- Items].

value_checksum({value, {_Tag, Index}}) -> Index;
value_checksum(none) -> 0.

run_kernel({compare, lt_first}, Inputs, N) when N >= 0 ->
    {lt_first_loop(Inputs, Inputs, N, 0), N};
run_kernel({compare, gt_first}, Inputs, N) when N >= 0 ->
    {gt_first_loop(Inputs, Inputs, N, 0), N};
run_kernel({tree, Action}, {Tree, Items}, N) when Action =:= hit; Action =:= miss ->
    {tree_lookup_loop(Items, Items, N, Tree, 0), N};
run_kernel({tree, update}, {Tree, Items}, N) ->
    {Sum, FinalTree} = tree_update_loop(Items, Items, N, 0, Tree, 0),
    {Sum, N, FinalTree}.

%% Keep each comparison ladder in the recursive loop: each input pays for the
%% branch sequence, including the true-equal path after both ordered tests.
lt_first_loop(_Inputs, _Cycle, 0, Sum) -> Sum;
lt_first_loop([], Cycle, N, Sum) -> lt_first_loop(Cycle, Cycle, N, Sum);
lt_first_loop([{A, B} | Rest], Cycle, N, Sum) ->
    Code = if
               A < B -> -1;
               A > B -> 1;
               true -> 0
           end,
    lt_first_loop(Rest, Cycle, N - 1, Sum + Code).

gt_first_loop(_Inputs, _Cycle, 0, Sum) -> Sum;
gt_first_loop([], Cycle, N, Sum) -> gt_first_loop(Cycle, Cycle, N, Sum);
gt_first_loop([{A, B} | Rest], Cycle, N, Sum) ->
    Code = if
               A > B -> 1;
               A < B -> -1;
               true -> 0
           end,
    gt_first_loop(Rest, Cycle, N - 1, Sum + Code).

tree_lookup_loop(_Items, _Cycle, 0, _Tree, Sum) -> Sum;
tree_lookup_loop([], Cycle, N, Tree, Sum) ->
    tree_lookup_loop(Cycle, Cycle, N, Tree, Sum);
tree_lookup_loop([{Key, _Expected} | Rest], Cycle, N, Tree, Sum) ->
    Code = case ?TREE_MODULE:lookup(Key, Tree) of
               none -> 0;
               {value, {_Tag, Index}} -> Index
           end,
    tree_lookup_loop(Rest, Cycle, N - 1, Tree, Sum + Code).

tree_update_loop(_Items, _Cycle, 0, _Pass, Tree, Sum) -> {Sum, Tree};
tree_update_loop([], Cycle, N, Pass, Tree, Sum) ->
    tree_update_loop(Cycle, Cycle, N, Pass + 1, Tree, Sum);
tree_update_loop([{Key, Index} | Rest], Cycle, N, Pass, Tree, Sum) ->
    State = Pass band 1,
    Updated = ?TREE_MODULE:update(Key, {updated, State, Index}, Tree),
    tree_update_loop(Rest, Cycle, N - 1, Pass, Updated, Sum + State + 1).

oracle_code(A, B) ->
    case {A < B, A > B} of
        {true, false} -> -1;
        {false, true} -> 1;
        {false, false} -> 0;
        Other -> erlang:error({invalid_order_predicates, Other, A, B})
    end.

validate_relation(any, _A, _B) -> ok;
validate_relation(lt, A, B) -> {true, false} = {A < B, A > B};
validate_relation(eq, A, B) -> {false, false} = {A < B, A > B};
validate_relation(gt, A, B) -> {false, true} = {A < B, A > B}.

validate_setup(#{kernel := {compare, _}, inputs := Pairs,
                 expected_codes := Codes, name := Name, relation := Relation},
              Base, Candidate) ->
    Codes = [oracle_code(A, B) || {A, B} <- Pairs],
    lists:foreach(fun({A, B}) -> validate_relation(Relation, A, B) end, Pairs),
    validate_identity(Name, Pairs),
    lists:foreach(fun(Module) ->
                          lists:foreach(fun({A, B}) ->
                                                Expected = oracle_code(A, B),
                                                {Expected, 1} = apply(
                                                  Module, run_kernel,
                                                  [{compare, lt_first}, [{A, B}], 1]),
                                                {Expected, 1} = apply(
                                                  Module, run_kernel,
                                                  [{compare, gt_first}, [{A, B}], 1])
                                        end, Pairs)
                  end, [Base, Candidate]),
    ok;
validate_setup(#{kernel := {tree, Action}, inputs := {Tree, Items},
                 initial := Initial, key_pairs := KeyPairs}, _Base, _Candidate) ->
    true = gb_trees:size(Tree) =:= length(Initial),
    case Action of
        hit ->
            lists:foreach(fun({Key, Expected}) ->
                                  Expected = ?TREE_MODULE:lookup(Key, Tree)
                          end, Items);
        miss ->
            lists:foreach(fun({Key, none}) ->
                                  none = ?TREE_MODULE:lookup(Key, Tree)
                          end, Items);
        update ->
            lists:foreach(fun({Key, _Index}) ->
                                  {value, _} = ?TREE_MODULE:lookup(Key, Tree)
                          end, Items)
    end,
    true = length(KeyPairs) =:= gb_trees:size(Tree),
    ok.

validate_identity(Name, Pairs) ->
    case {lists:suffix("shared_eq", Name), lists:suffix("copied_eq", Name)} of
        {true, false} ->
            lists:foreach(fun({A, B}) ->
                                  true = (A =:= B),
                                  true = erts_debug:same(A, B)
                          end, Pairs);
        {false, true} ->
            lists:foreach(fun({A, B}) ->
                                  true = (A =:= B),
                                  false = erts_debug:same(A, B)
                          end, Pairs);
        _ -> ok
    end.

warm({_Variant, Module}, Kernel, Inputs, N) ->
    erlang:garbage_collect(),
    Result = apply(Module, run_kernel, [Kernel, Inputs, N]),
    validate_kernel_result(Kernel, Inputs, N, Result),
    ok.

choose_iterations(Base, Candidate, Kernel, Inputs, TargetMs, MaxIterations, Options) ->
    PilotMaxN = min(MaxIterations, maps:get(pilot_max_iterations, Options)),
    PilotMinNs = maps:get(pilot_min_ms, Options) * 1000000,
    PilotMaxNs = maps:get(pilot_max_ms, Options) * 1000000,
    {BaseNs, BaseN} = pilot_ns(Base, Kernel, Inputs, PilotMaxN,
                               PilotMinNs, PilotMaxNs),
    {CandidateNs, CandidateN} = pilot_ns(Candidate, Kernel, Inputs, PilotMaxN,
                                         PilotMinNs, PilotMaxNs),
    BaseNsPerOp = max(1, BaseNs div BaseN),
    CandidateNsPerOp = max(1, CandidateNs div CandidateN),
    GeometricNsPerOp = max(1, trunc(math:sqrt(BaseNsPerOp * CandidateNsPerOp))),
    TargetOps = max(1, (TargetMs * 1000000) div GeometricNsPerOp),
    min(MaxIterations, TargetOps).

pilot_ns(Module, Kernel, Inputs, MaxN, MinNs, MaxNs) ->
    pilot_ns(Module, Kernel, Inputs, min(16, MaxN), MaxN, MinNs, MaxNs, 0, 0).

pilot_ns(Module, Kernel, Inputs, N, MaxN, MinNs, MaxNs, TotalNs, TotalN) ->
    erlang:garbage_collect(),
    T0 = erlang:monotonic_time(nanosecond),
    Result = apply(Module, run_kernel, [Kernel, Inputs, N]),
    T1 = erlang:monotonic_time(nanosecond),
    validate_kernel_result(Kernel, Inputs, N, Result),
    ElapsedNs = T1 - T0,
    NewTotalNs = TotalNs + ElapsedNs,
    NewTotalN = TotalN + N,
    case NewTotalNs >= MinNs orelse NewTotalNs >= MaxNs orelse N >= MaxN of
        true -> {NewTotalNs, NewTotalN};
        false ->
            RemainingNs = min(MinNs - NewTotalNs, MaxNs - NewTotalNs),
            NextN = min(MaxN,
                        max(1, (RemainingNs * N + ElapsedNs - 1) div
                                   max(1, ElapsedNs))),
            pilot_ns(Module, Kernel, Inputs, NextN, MaxN,
                     MinNs, MaxNs, NewTotalNs, NewTotalN)
    end.

run_rounds(_Case, _Base, _Candidate, Options, _N, Round, _Index)
  when Round > map_get(rounds, Options) ->
    ok;
run_rounds(Case, Base, Candidate, Options, N, Round, Index) ->
    {First, Second} = variant_order(maps:get(variant_order, Options), Round, Index,
                                    Base, Candidate),
    measure_variant(First, Case, N, Round),
    measure_variant(Second, Case, N, Round),
    run_rounds(Case, Base, Candidate, Options, N, Round + 1, Index).

variant_order(VariantOrder, Round, Index, Base, Candidate) ->
    Reverse = VariantOrder =:= candidate_first,
    Parity = (Round + Index) rem 2,
    FirstIsBase = (Parity =:= 0) =/= Reverse,
    case FirstIsBase of
        true -> {{baseline, Base}, {candidate, Candidate}};
        false -> {{candidate, Candidate}, {baseline, Base}}
    end.

measure_variant({Variant, Module}, Case, N, Round) ->
    Kernel = maps:get(kernel, Case),
    Inputs = maps:get(inputs, Case),
    erlang:garbage_collect(),
    Gc1 = erlang:statistics(garbage_collection),
    T0 = erlang:monotonic_time(nanosecond),
    Result = apply(Module, run_kernel, [Kernel, Inputs, N]),
    T1 = erlang:monotonic_time(nanosecond),
    Gc2 = erlang:statistics(garbage_collection),
    validate_kernel_result(Kernel, Inputs, N, Result),
    validate_after_measurement(Case, N, Result),
    GcDelta = gc_delta(Gc1, Gc2),
    Ns = (T1 - T0) / N,
    io:format("~s,~s,~B,~s,~B,~.2f,~B,~s~n",
              [maps:get(name, Case), atom_to_list(maps:get(order, Case)),
               Round, atom_to_list(Variant), N, Ns,
               result_checksum(Result), GcDelta]),
    ok.

validate_kernel_result({compare, _}, Inputs, N, {Checksum, N}) ->
    Expected = repeated_sum([oracle_code(A, B) || {A, B} <- Inputs], N),
    Expected = Checksum,
    ok;
validate_kernel_result({tree, Action}, {Tree, Items}, N, Result)
  when Action =:= hit; Action =:= miss ->
    {Checksum, N} = Result,
    Expected = repeated_sum(tree_codes(Action, Items), N),
    Expected = Checksum,
    true = is_integer(gb_trees:size(Tree)),
    ok;
validate_kernel_result({tree, update}, {_Tree, Items}, N, {Checksum, N, FinalTree}) ->
    Expected = update_checksum(length(Items), N),
    Expected = Checksum,
    true = is_tuple(FinalTree),
    ok.

validate_after_measurement(#{kernel := {tree, update},
                             inputs := {InitialTree, Items}}, N,
                           {_Checksum, N, FinalTree}) ->
    ok = validate_updated_tree(InitialTree, Items, N, FinalTree);
validate_after_measurement(_Case, _N, _Result) ->
    ok.

validate_updated_tree(InitialTree, Items, N, FinalTree) ->
    ItemCount = length(Items),
    Q = N div ItemCount,
    R = N rem ItemCount,
    InitialPairs = gb_trees:to_list(InitialTree),
    QueryPositions = maps:from_list(
                       [{Key, Position}
                        || {{Key, _Value}, Position} <-
                               lists:zip(Items, lists:seq(0, ItemCount - 1))]),
    Expected = [expected_updated_pair(Pair, maps:get(element(1, Pair), QueryPositions),
                                      Q, R)
                || Pair <- InitialPairs],
    Expected = gb_trees:to_list(FinalTree),
    ok.

expected_updated_pair({Key, {original, Index}}, Position, Q, R) ->
    LastPass = if
                   Position < R -> Q;
                   Q > 0 -> Q - 1;
                   true -> -1
               end,
    case LastPass of
        -1 -> {Key, {original, Index}};
        _ -> {Key, {updated, LastPass band 1, Index}}
    end.

update_checksum(ItemCount, N) ->
    Q = N div ItemCount,
    R = N rem ItemCount,
    EvenPasses = (Q + 1) div 2,
    OddPasses = Q div 2,
    SumPasses = ItemCount * (EvenPasses + 2 * OddPasses),
    SumPasses + R * ((Q band 1) + 1).

repeated_sum(Codes, N) ->
    Len = length(Codes),
    Full = N div Len,
    Rem = N rem Len,
    Full * sum(Codes) + sum(lists:sublist(Codes, Rem)).

result_checksum({Checksum, _N}) -> Checksum;
result_checksum({Checksum, _N, _Tree}) -> Checksum.

gc_delta({Count0, Words0, _}, {Count1, Words1, _}) ->
    lists:flatten(io_lib:format("~B:~B", [Count1 - Count0, Words1 - Words0])).

sum(Values) -> lists:sum(Values).

case_name(Parts) ->
    lists:flatten(lists:join("_", [atom_to_list(Part) || Part <- Parts])).

shuffle(List, Seed) ->
    State0 = rand:seed_s(exsplus, {Seed + 101, Seed + 211, Seed + 307}),
    {Tagged, _State1} = lists:mapfoldl(
                          fun(Item, State0a) ->
                                  {Key, State1a} = rand:uniform_s(16#7fffffff, State0a),
                                  {{Key, Item}, State1a}
                          end, State0, List),
    [Item || {_Key, Item} <- lists:keysort(1, Tagged)].
