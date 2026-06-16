#!/usr/bin/env escript
%% -*- erlang -*-
%%! -noshell
%%
%% Lightweight static audit for ARM64 BeamAsm improvement candidates.
%%
%% This script is intentionally conservative: it only checks facts that can be
%% proven from checked-in source. Source-to-BEAM-to-JIT dump tests are still
%% required before implementing an optimization.

main(["--source-probes"]) ->
    run_source_probes();
main(["--bench-stats"]) ->
    run_bench_stats();
main(_) ->
    Root = repo_root(),
    Checks = checks(Root),
    lists:foreach(fun print_check/1, Checks),
    case [C || C = #{state := failed} <- Checks] of
        [] ->
            halt(0);
        _ ->
            halt(1)
    end.

repo_root() ->
    Script = escript:script_name(),
    filename:absname(filename:join(filename:dirname(Script),
                                   "../../../../..")).

checks(Root) ->
    ArmOps = read_file(Root, "erts/emulator/beam/jit/arm/ops.tab"),
    X86Ops = read_file(Root, "erts/emulator/beam/jit/x86/ops.tab"),
    ArmCommon = read_file(Root, "erts/emulator/beam/jit/arm/instr_common.cpp"),
    X86Common = read_file(Root, "erts/emulator/beam/jit/x86/instr_common.cpp"),
    ArmArith = read_file(Root, "erts/emulator/beam/jit/arm/instr_arith.cpp"),
    X86Arith = read_file(Root, "erts/emulator/beam/jit/x86/instr_arith.cpp"),
    ArmGuardBifs = read_file(Root, "erts/emulator/beam/jit/arm/instr_guard_bifs.cpp"),
    ArmBs = read_file(Root, "erts/emulator/beam/jit/arm/instr_bs.cpp"),
    X86Bs = read_file(Root, "erts/emulator/beam/jit/x86/instr_bs.cpp"),
    ArmPred = read_file(Root, "erts/emulator/beam/jit/arm/predicates.tab"),
    BeamJitCommon = read_file(Root, "erts/emulator/beam/jit/beam_jit_common.cpp"),
    BeamJitMain = read_file(Root, "erts/emulator/beam/jit/beam_jit_main.cpp"),
    BeamBifLoad = read_file(Root, "erts/emulator/beam/beam_bif_load.c"),

    [gap("arm-splus1",
         contains(ArmOps, "u$bif:erlang:splus/1") andalso
             contains(ArmOps, "i_plus Fail Live Src i Dst") andalso
             contains(X86Ops, "u$bif:erlang:splus/1"),
         "ARM now lowers splus/1 through i_plus with identity RHS, matching the x86 shape."),
     gap("eq-ne-operand-duplication",
         contains(ArmCommon, "always_one_of<BeamTypeId::Cons, BeamTypeId::AlwaysBoxed>(X) ||\n        always_one_of<BeamTypeId::Cons, BeamTypeId::AlwaysBoxed>(Y)") andalso
             not contains(ArmCommon, "always_one_of<BeamTypeId::Cons, BeamTypeId::AlwaysBoxed>(X) ||\n        always_one_of<BeamTypeId::Cons, BeamTypeId::AlwaysBoxed>(X)"),
         "ARM equality/non-equality now test X and Y when checking whether one operand is never immediate."),
     gap("arm-missing-eq-shared",
         not contains(ArmCommon, "emit_arith_eq_shared") andalso
             contains(X86Common, "emit_arith_eq_shared"),
         "x86 has equality-specific arith compare fragment; ARM only has generic compare."),
     gap("literal-map-get-bif",
         contains(ArmOps, "u$bif:erlang:map_get/2") andalso
             contains(ArmOps, "bif_map_get") andalso
             contains(ArmOps, "i_get_map_element_hash") andalso
             contains(ArmGuardBifs, "Fail.get() == 0 && Key.isConstant() && !Key.isImmed()") andalso
             contains(ArmGuardBifs, "get_map_element_hash"),
         "ARM body map_get/2 now uses prehashed runtime lookup for boxed literal keys."),
     gap("literal-is-map-key-bif",
         contains(ArmOps, "u$bif:erlang:is_map_key/2") andalso
             contains(ArmOps, "bif_is_map_key") andalso
             contains(ArmGuardBifs, "emit_handle_is_map_key_badmap") andalso
             contains(ArmGuardBifs, "hashmap_make_hash(get_constant_key())") andalso
             contains(ArmGuardBifs, "get_i_get_map_element_hash_shared"),
         "ARM now inlines is_map_key/2 for untyped maps and prehashes immediate literal keys."),
     gap("narrow-put-list2",
         contains(ArmOps, "put_list2") andalso
             contains(ArmOps, "put_list Hd1=y Tl Dst | put_list Hd2=y Dst2 Dst3") andalso
             not contains(ArmOps, "put_list3"),
         "ARM list construction fusion is limited to the current put_list2 shape."),
     gap("narrow-epilogue-fusion",
         contains(ArmOps, "move y==0 x==0 | deallocate u==1 | return") andalso
             not contains(ArmOps, "move_deallocate_return ") andalso
             contains(ArmOps, "try_end _Y | move Src Dst | deallocate N"),
         "ARM has exact epilogue/try_end fusion patterns but no broader family."),
     gap("pair-only-move-fusion",
         contains(ArmOps, "store_two_values") andalso
             contains(ArmOps, "load_two_xregs") andalso
             not contains(ArmOps, "store_three") andalso
             not contains(ArmOps, "load_three"),
         "ARM move fusion has pair rules but no triple/quad family."),
     gap("register-backed-xregs-boundary",
         contains(ArmPred, "const Uint num_register_backed_xregs = 6") andalso
             contains(ArmPred, "A1.val >= num_register_backed_xregs"),
         "Consecutive XREG pairing excludes register-backed X registers."),
     gap("arith-guard-shared-fragments",
         contains(ArmArith, "emit_i_plus") andalso
             contains(ArmArith, "emit_enter_runtime") andalso
             not contains(ArmArith, "emit_plus_guard_shared"),
         "ARM arithmetic fallbacks are local runtime crossings, not shared guard fragments."),
     gap("bitwise-guard-shared-fragments",
         contains(X86Arith, "emit_bitwise_fallback_guard") andalso
             not contains(ArmArith, "emit_bitwise_fallback_guard"),
         "x86 has a shared bitwise guard fallback; ARM does not."),
     gap("binary-unknown-zero-fill",
         contains(ArmBs, "void BeamModuleAssembler::set_zero") andalso
             contains(ArmBs, "a.strb(ZERO.w(), a64::Mem(TMP1).post(1))") andalso
             not contains(ArmBs, "dc_zva") andalso
             not contains(ArmBs, "mops"),
         "ARM set_zero has byte-loop fallback and no DC ZVA/MOPS path."),
     gap("binary-unaligned-byte-loop",
         contains(ArmBs, "emit_store_unaligned") andalso
             contains(ArmBs, "a.strb(bitdata.w(), a64::Mem(TMP1).post(1))"),
         "ARM unaligned binary store helper contains a byte-at-a-time loop."),
     gap("binary-cpu-feature-gap",
         contains(X86Bs, "hasCpuFeature(CpuFeatures::X86") andalso
             not contains(ArmBs, "hasCpuFeature(CpuFeatures::ARM"),
         "x86 binary emitters use CPU features; ARM binary emitters currently do not."),
     gap("fixed-select-threshold",
         contains(ArmOps, "use_jump_tab(Size, Rest, 6)") andalso
             contains(X86Ops, "use_jump_tab(Size, Rest, 6)"),
         "select jump-table threshold is a fixed copied value, not measured/tuned for ARM."),
     gap("module-seal-already-batched",
         contains(BeamJitCommon, "The user will call `beamasm_seal_module`") andalso
             contains(BeamJitMain, "beamasm_seal_module"),
         "Downgrade: module codegen already defers executable protection until sealing."),
     gap("module-purge-exists",
         contains(BeamBifLoad, "beamasm_unregister_metadata") andalso
             contains(BeamBifLoad, "beamasm_purge_module"),
         "Downgrade: OTP already purges unloaded module JIT code; aging would be new policy.")
    ].

read_file(Root, Path) ->
    Abs = filename:join(Root, Path),
    case file:read_file(Abs) of
        {ok, Bin} ->
            binary_to_list(Bin);
        {error, Reason} ->
            io:format(standard_error, "failed to read ~s: ~p~n", [Abs, Reason]),
            halt(2)
    end.

contains(Haystack, Needle) ->
    string:find(Haystack, Needle) =/= nomatch.

gap(Id, true, Detail) ->
    #{id => Id, state => present, detail => Detail};
gap(Id, false, Detail) ->
    #{id => Id, state => failed, detail => Detail}.

print_check(#{id := Id, state := State, detail := Detail}) ->
    io:format("~s ~s - ~s~n", [string:uppercase(atom_to_list(State)), Id, Detail]).

run_source_probes() ->
    Dir = make_temp_dir(),
    Source = filename:join(Dir, "arm64_jit_lowering_probe.erl"),
    ok = file:write_file(Source, source_probe_module()),
    try
        case compile:file(Source, [to_asm, binary, report]) of
            {ok, arm64_jit_lowering_probe, Asm} ->
                Probes = source_probes(Asm),
                lists:foreach(fun print_probe/1, Probes),
                halt(0);
            Other ->
                io:format(standard_error, "source probe compile failed: ~p~n",
                          [Other]),
                halt(2)
        end
    after
        _ = file:del_dir_r(Dir)
    end.

make_temp_dir() ->
    Base0 = os:getenv("TMPDIR"),
    Base = case Base0 of
               false -> "/tmp";
               _ -> Base0
           end,
    Dir = filename:join(Base,
                        "arm64_jit_lowering_probe_" ++
                            integer_to_list(erlang:unique_integer([positive]))),
    ok = file:make_dir(Dir),
    Dir.

source_probe_module() ->
    <<"-module(arm64_jit_lowering_probe).\n"
      "-export([unary_plus/1,map_get_lit/1,map_get_bin_lit/1,is_map_key_lit/1,cons3/4]).\n"
      "unary_plus(X) -> +X.\n"
      "map_get_lit(M) -> map_get(a, M).\n"
      "map_get_bin_lit(M) -> map_get(<<\"a\">>, M).\n"
      "is_map_key_lit(M) -> is_map_key(a, M).\n"
      "cons3(A, B, C, T) -> [A, B, C | T].\n">>.

source_probes(Asm) ->
    [probe("source-splus1",
           contains_gc_bif(Asm, '+', 1) orelse
               contains_extfunc(Asm, erlang, splus, 1),
           "normal '+X' source still lowers to unary plus BIF form"),
     probe("source-map-get-literal-bif",
           contains_bif(Asm, map_get, 2) orelse
               contains_extfunc(Asm, erlang, map_get, 2),
           "normal map_get(a, M) source still lowers to map_get/2 BIF form"),
     probe("source-map-get-boxed-literal-bif",
           contains_bif_arg(Asm, map_get, 2, {literal, <<"a">>}),
           "normal map_get(<<\"a\">>, M) source reaches map_get/2 with a boxed literal key"),
     probe("source-is-map-key-literal-bif",
           contains_bif(Asm, is_map_key, 2) orelse
               contains_extfunc(Asm, erlang, is_map_key, 2),
           "normal is_map_key(a, M) source still lowers to is_map_key/2 BIF form"),
     probe("source-cons3-put-list-chain",
           count_atom(Asm, put_list) >= 3,
           "normal [A, B, C | T] source still has a put_list chain")].

probe(Id, true, Detail) ->
    #{id => Id, state => present, detail => Detail};
probe(Id, false, Detail) ->
    #{id => Id, state => missing, detail => Detail}.

print_probe(#{id := Id, state := State, detail := Detail}) ->
    io:format("~s ~s - ~s~n", [string:uppercase(atom_to_list(State)), Id, Detail]).

run_bench_stats() ->
    Samples = read_bench_samples([]),
    case Samples of
        [] ->
            io:format(standard_error, "no numeric benchmark samples on stdin~n", []),
            halt(2);
        _ ->
            print_bench_stats(Samples),
            halt(0)
    end.

read_bench_samples(Acc) ->
    case io:get_line("") of
        eof ->
            lists:reverse(Acc);
        Line ->
            Tokens = string:tokens(Line, " \t\r\n,"),
            Values = [Value || Token <- Tokens,
                               {ok, Value} <- [parse_integer(Token)]],
            read_bench_samples(lists:reverse(Values) ++ Acc)
    end.

parse_integer(Token) ->
    try {ok, list_to_integer(Token)}
    catch error:badarg -> error
    end.

print_bench_stats(Samples) ->
    Sorted = lists:sort(Samples),
    N = length(Sorted),
    Min = hd(Sorted),
    Max = lists:last(Sorted),
    Median = median(Sorted, N),
    Avg = lists:sum(Sorted) / N,
    StdDev = sample_stddev(Sorted, Avg, N),
    io:format("n=~p min=~p median=~.1f avg=~.1f stddev=~.1f max=~p~n",
              [N, Min, Median, Avg, StdDev, Max]).

median(Sorted, N) when N rem 2 =:= 1 ->
    lists:nth((N + 1) div 2, Sorted) * 1.0;
median(Sorted, N) ->
    (lists:nth(N div 2, Sorted) + lists:nth(N div 2 + 1, Sorted)) / 2.

sample_stddev(_Samples, _Avg, 1) ->
    0.0;
sample_stddev(Samples, Avg, N) ->
    SumSquares = lists:sum([math:pow(Sample - Avg, 2) || Sample <- Samples]),
    math:sqrt(SumSquares / (N - 1)).

contains_extfunc(Term, M, F, A) ->
    contains_term(Term, {extfunc, M, F, A}).

contains_gc_bif({gc_bif, Name, _Fail, Arity, _Args, _Dst}, Name, Arity) ->
    true;
contains_gc_bif(Term, Name, Arity) when is_tuple(Term) ->
    contains_gc_bif(tuple_to_list(Term), Name, Arity);
contains_gc_bif([Head | Tail], Name, Arity) ->
    contains_gc_bif(Head, Name, Arity) orelse
        contains_gc_bif(Tail, Name, Arity);
contains_gc_bif(_Term, _Name, _Arity) ->
    false.

contains_bif({bif, Name, _Fail, Args, _Dst}, Name, Arity)
        when length(Args) =:= Arity ->
    true;
contains_bif(Term, Name, Arity) when is_tuple(Term) ->
    contains_bif(tuple_to_list(Term), Name, Arity);
contains_bif([Head | Tail], Name, Arity) ->
    contains_bif(Head, Name, Arity) orelse contains_bif(Tail, Name, Arity);
contains_bif(_Term, _Name, _Arity) ->
    false.

contains_bif_arg({bif, Name, _Fail, Args, _Dst}, Name, Arity, Arg)
        when length(Args) =:= Arity ->
    lists:member(Arg, Args);
contains_bif_arg(Term, Name, Arity, Arg) when is_tuple(Term) ->
    contains_bif_arg(tuple_to_list(Term), Name, Arity, Arg);
contains_bif_arg([Head | Tail], Name, Arity, Arg) ->
    contains_bif_arg(Head, Name, Arity, Arg) orelse
        contains_bif_arg(Tail, Name, Arity, Arg);
contains_bif_arg(_Term, _Name, _Arity, _Arg) ->
    false.

contains_term(Term, Needle) when Term =:= Needle ->
    true;
contains_term(Term, Needle) when is_tuple(Term) ->
    contains_term(tuple_to_list(Term), Needle);
contains_term([Head | Tail], Needle) ->
    contains_term(Head, Needle) orelse contains_term(Tail, Needle);
contains_term(_Term, _Needle) ->
    false.

count_atom(Term, Atom) when Term =:= Atom ->
    1;
count_atom(Term, Atom) when is_tuple(Term) ->
    count_atom(tuple_to_list(Term), Atom);
count_atom([Head | Tail], Atom) ->
    count_atom(Head, Atom) + count_atom(Tail, Atom);
count_atom(_Term, _Atom) ->
    0.
