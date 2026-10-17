%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 1999-2026. All Rights Reserved.
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

-module(op_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, suite/0,
         bsl_bsr/1,logical/1,t_not/1,relop_simple/1,relop/1,
         complex_relop/1,unsafe_fusing/1,
         range_tests/1,combined_relops/1,typed_relop/1,
         term_equivalence/1,atom_ordering/1,mixed_small_float/1,
         small_boxed_ordering/1,
         hamt_comparison_paths/1,
         cons_boxed_ordering/1,
         list_small_head_ordering/1,
         is_in_range/1]).

-import(lists, [foldl/3,flatmap/2]).

suite() ->
    [{ct_hooks,[ts_install_cth]},
     {timetrap, {minutes, 5}}].

all() ->
    [bsl_bsr, logical, t_not, relop_simple, relop,
     complex_relop, unsafe_fusing, range_tests,
     combined_relops, typed_relop, term_equivalence,
     atom_ordering, mixed_small_float, small_boxed_ordering,
     hamt_comparison_paths, cons_boxed_ordering, list_small_head_ordering,
     is_in_range].

%% Test the bsl and bsr operators.
bsl_bsr(Config) when is_list(Config) ->
    RawValues = [-16#8000009-2,-1,0,1,2,73,16#8000000,bad,[]],

    [bsl_bsr_const(V) || V <- RawValues],

    Vs = [unvalue(V) || V <- RawValues],
    %% Try to use less memory by splitting the cases

    Cases1 = [{Op,X,Y} || Op <- ['bsl'], X <- Vs, Y <- Vs],
    N1 = length(Cases1),
    run_test_module(Cases1, false),

    Cases2 = [{Op,X,Y} || Op <- ['bsr'], X <- Vs, Y <- Vs],
    N2 = length(Cases2),
    run_test_module(Cases2, false),

    {comment,integer_to_list(N1 + N2) ++ " cases"}.

%% Tests constant-argument optimizations in `bsl`/`bsr`
bsl_bsr_const(A) ->
    BSL = id('bsl'),
    BSR = id('bsr'),

    bsl_bsr_compare_results(fun() -> erlang:BSL(1, A) end, fun() -> 1 bsl A end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(3, A) end, fun() -> 3 bsl A end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(7, A) end, fun() -> 7 bsl A end),

    bsl_bsr_compare_results(fun() -> erlang:BSL(A, 1) end, fun() -> A bsl 1 end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(A, 3) end, fun() -> A bsl 3 end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(A, 7) end, fun() -> A bsl 7 end),

    bsl_bsr_compare_results(fun() -> erlang:BSL(-2, A) end, fun() -> -2 bsl A end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(-4, A) end, fun() -> -4 bsl A end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(-8, A) end, fun() -> -8 bsl A end),

    bsl_bsr_compare_results(fun() -> erlang:BSL(A, -2) end, fun() -> A bsl -2 end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(A, -4) end, fun() -> A bsl -4 end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(A, -8) end, fun() -> A bsl -8 end),

    bsl_bsr_compare_results(fun() -> erlang:BSR(1, A) end, fun() -> 1 bsr A end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(3, A) end, fun() -> 3 bsr A end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(7, A) end, fun() -> 7 bsr A end),

    bsl_bsr_compare_results(fun() -> erlang:BSR(A, 1) end, fun() -> A bsr 1 end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(A, 3) end, fun() -> A bsr 3 end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(A, 7) end, fun() -> A bsr 7 end),

    bsl_bsr_compare_results(fun() -> erlang:BSR(-2, A) end, fun() -> -2 bsr A end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(-4, A) end, fun() -> -4 bsr A end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(-8, A) end, fun() -> -8 bsr A end),

    bsl_bsr_compare_results(fun() -> erlang:BSR(A, -2) end, fun() -> A bsr -2 end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(A, -4) end, fun() -> A bsr -4 end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(A, -8) end, fun() -> A bsr -8 end),


    %% These numbers can be shifted left one or zero times while remaining a
    %% small on 32-bit platforms.
    %%
    %% The test relies on the compiler turning these into constants.
    HighEdge32 = (1 bsl (32 - 6)) - 1,
    LowEdge32 = -(1 bsl (32 - 6)),

    bsl_bsr_compare_results(fun() -> erlang:BSL(HighEdge32, A) end, fun() -> HighEdge32 bsl A end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(LowEdge32, A) end, fun() -> LowEdge32 bsl A end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(HighEdge32, A) end, fun() -> HighEdge32 bsr A end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(LowEdge32, A) end, fun() -> LowEdge32 bsr A end),

    HighEdge64 = (1 bsl (64 - 6)) - 1,
    LowEdge64 = -(1 bsl (64 - 6)),

    bsl_bsr_compare_results(fun() -> erlang:BSL(HighEdge64, A) end, fun() -> HighEdge64 bsl A end),
    bsl_bsr_compare_results(fun() -> erlang:BSL(LowEdge64, A) end, fun() -> LowEdge64 bsl A end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(HighEdge64, A) end, fun() -> HighEdge64 bsr A end),
    bsl_bsr_compare_results(fun() -> erlang:BSR(LowEdge64, A) end, fun() -> LowEdge64 bsr A end),

    ok.

bsl_bsr_compare_results(Fun1, Fun2) ->
    R1 = try Fun1() catch Class1:Reason1 -> {Class1, Reason1} end,
    R2 = try Fun2() catch Class2:Reason2 -> {Class2, Reason2} end,
    true = R1 =:= R2,
    ok.

%% Test the logical operators and internal BIFs.
logical(Config) when is_list(Config) ->
    Vs0 = [true,false,bad],
    Vs = [unvalue(V) || V <- Vs0],
    Cases = [{Op,X,Y} || Op <- ['and','or','xor'], X <- Vs, Y <- Vs],
    run_test_module(Cases, false),
    {comment,integer_to_list(length(Cases)) ++ " cases"}.

%% Test the not operator and internal BIFs.
t_not(Config) when is_list(Config) ->
    Cases = [{'not',unvalue(V)} || V <- [true,false,42,bad]],
    run_test_module(Cases, false),
    {comment,integer_to_list(length(Cases)) ++ " cases"}.

%% Test that simple relations between relation operators hold.
relop_simple(Config) when is_list(Config) ->
    Big1 = 19738924729729787487784874,
    Big2 = 38374938373887374983978484,
    F1 = float(Big1),
    F2 = float(Big2),
    T1 = erlang:make_tuple(3,87),
    T2 = erlang:make_tuple(3,87),
    Terms = [-F2,Big2,-F1,-Big1,-33,-33.0,0,0.0,-0.0,42,42.0,Big1,F1,Big2,F2,
             a,b,{T1,a},{T2,b},[T1,Big1],[T2,Big2]],

    Combos = [{V1,V2} || V1 <- Terms, V2 <- Terms],

    lists:foreach(fun({A,B}) -> relop_simple_do(A,B) end,
                  Combos),

    repeat(fun() ->
                   Size = rand:uniform(100),
                   Rnd1 = make_rand_term(Size),
                   {Rnd2,0} = clone_and_mutate(Rnd1, rand:uniform(Size)),
                   relop_simple_do(Rnd1,Rnd2)
           end,
           1000),
    ok.

relop_simple_do(V1,V2) ->
    %%io:format("compare ~p\n   and  ~p\n",[V1,V2]),

    L = V1 < V2,
    L = not id(V1 >= V2),
    L = V2 > V1,
    L = not id(V2 =< V1),

    LE = V1 =< V2,
    LE = not id(V1 > V2),
    LE = V2 >= V1,
    LE = not id(V2 < V1),

    G = id(if
               V1 > V2 -> id(true);
               true -> false
           end),
    G = id(V1 > V2),
    G = not id(V1 =< V2),
    G = id(V2 < V1),
    G = not id(V2 >= V1),

    GE = id(V1 >= V2),
    GE = not id(V1 < V2),
    GE = id(V2 =< V1),
    GE = not id(V2 > V1),

    ID = V1 =:= V2,
    ID = V2 =:= V1,
    ID = not id(V1 =/= V2),
    ID = not id(V2 =/= V1),

    implies(ID, V1 == V2),

    EQ = V1 == V2,
    EQ = V2 == V1,
    EQ = not (V1 /= V2),
    EQ = not (V2 /= V1),

    case {L, EQ, ID, G, cmp_emu(V1,V2)} of
        { true, false, false, false, -1} -> ok;
        {false, true,  false, false,  0} -> ok;
        {false, true,   true, false,  0} -> ok;
        {false, false, false, true,  +1} -> ok
    end,

    LE = L orelse EQ,
    GE = G orelse EQ,

    relop_simple_do1(id(V1), id(V2)).

relop_simple_do1(V1, V2) ->
    if
        is_integer(V1), -1 bsl 56 =< V1, V1 =< 1 bsl 56,
        is_integer(V2), V2 < 1 bsl 56 ->
            L = id(if
                       V1 < V2 -> id(true);
                       true -> false
                   end),
            L = id(V1 < V2),
            L = not id(V1 >= V2),
            L = id(V2 > V1),
            L = not id(V2 =< V1),

            LE = id(if
                        V1 =< V2 -> id(true);
                        true -> false
                   end),
            LE = id(V1 =< V2),
            LE = not id(V1 > V2),
            LE = id(V2 >= V1),
            LE = not id(V2 < V1),

            G = id(if
                       V1 > V2 -> id(true);
                       true -> false
                   end),
            G = id(V1 > V2),
            G = not id(V1 =< V2),
            G = id(V2 < V1),
            G = not id(V2 >= V1),

            GE = id(if
                        V1 >= V2 -> id(true);
                        true -> false
                   end),
            GE = id(V1 >= V2),
            GE = not id(V1 < V2),
            GE = id(V2 =< V1),
            GE = not id(V2 > V1),

            ok;
        true ->
            ok
    end,
    relop_simple_do2(id(V1), id(V2)).

relop_simple_do2(V1, V2) ->
    if
        is_integer(V1), -1 bsl 56 =< V1, V1 =< 1 bsl 56,
        is_integer(V2), V2 > 1 bsl 50 ->
            L = id(if
                       V1 < V2 -> id(true);
                       true -> false
                   end),
            L = id(V1 < V2),
            L = not id(V1 >= V2),
            L = id(V2 > V1),
            L = not id(V2 =< V1),

            LE = id(if
                        V1 =< V2 -> id(true);
                        true -> false
                   end),
            LE = id(V1 =< V2),
            LE = not id(V1 > V2),
            LE = id(V2 >= V1),
            LE = not id(V2 < V1),

            G = id(V1 > V2),
            G = not id(V1 =< V2),
            G = id(V2 < V1),
            G = not id(V2 >= V1),

            GE = id(if
                        V1 >= V2 -> id(true);
                        true -> false
                   end),
            GE = id(V1 >= V2),
            GE = not id(V1 < V2),
            GE = id(V2 =< V1),
            GE = not id(V2 > V1),

            ok;
        true ->
            ok
    end,
    relop_simple_do3(id(V1), id(V2)).

relop_simple_do3(V1, V2) ->
    if
        is_integer(V1),
        is_integer(V2), -1 bsl 56 =< V2, V2 =< 1 bsl 56 ->
            L = id(if
                       V1 < V2 -> id(true);
                       true -> false
                   end),
            L = id(V1 < V2),
            L = not id(V1 >= V2),
            L = id(V2 > V1),
            L = not id(V2 =< V1),

            LE = id(if
                        V1 =< V2 -> id(true);
                        true -> false
                   end),
            LE = id(V1 =< V2),
            LE = not id(V1 > V2),
            LE = id(V2 >= V1),
            LE = not id(V2 < V1),

            G = id(if
                       V1 > V2 -> id(true);
                       true -> false
                   end),
            G = V1 > V2,
            G = not id(V1 =< V2),
            G = V2 < V1,
            G = not id(V2 >= V1),

            GE = id(if
                        V1 >= V2 -> id(true);
                        true -> false
                    end),
            GE = id(V1 >= V2),
            GE = not id(V1 < V2),
            GE = id(V2 =< V1),
            GE = not id(V2 > V1),

            ok;
        true ->
            ok
    end,
    ok.

implies(false, _) -> ok;
implies(true, true) -> ok.

%% Emulate internal "cmp"
cmp_emu(A,B) when is_tuple(A), is_tuple(B) ->
    SA = size(A),
    SB = size(B),
    if SA =:= SB -> cmp_emu(tuple_to_list(A),tuple_to_list(B));
       SA > SB -> +1;
       SA < SB -> -1
    end;
cmp_emu([A|TA],[B|TB]) ->
    case cmp_emu(A,B) of
        0   -> cmp_emu(TA,TB);
        CMP -> CMP
    end;
cmp_emu(A,B) ->
    %% We cheat and use real "cmp" for the primitive types.
    if A < B -> -1;
       A > B -> +1;
       true -> 0
    end.					              

make_rand_term(1) ->
    make_rand_term_single();
make_rand_term(Arity) ->
    case rand:uniform(3) of
        1 ->
            make_rand_list(Arity);
        2 ->
            list_to_tuple(make_rand_list(Arity));
        3 ->
            {Car,Rest} = make_rand_term_rand_size(Arity),
            [Car|make_rand_term(Rest)]
    end.

make_rand_term_single() ->
    Range = 1 bsl rand:uniform(200),
    case rand:uniform(12) of
        1 -> random;
        2 -> uniform;
        3 -> rand:uniform(Range) - (Range div 2);
        4 -> Range * (rand:uniform() - 0.5);
        5 -> 0;
        6 -> 0.0;
        7 -> make_ref();
        8 -> self();
        9 -> term_to_binary(rand:uniform(Range));
        10 -> fun(X) -> X*Range end; 
        11 -> fun(X) -> X/Range end;
        12 -> []
    end.	    

make_rand_term_rand_size(1) ->
    {make_rand_term(1), 0};
make_rand_term_rand_size(MaxArity) ->
    Arity = rand:uniform(MaxArity-1),
    {make_rand_term(Arity), MaxArity-Arity}.

make_rand_list(0) -> [];
make_rand_list(Arity) ->
    {Term, Rest} = make_rand_term_rand_size(Arity),
    [Term | make_rand_list(Rest)].


clone_and_mutate(Term, 0) ->
    {clone(Term), 0};
clone_and_mutate(_Term, 1) ->
    {Mutation, _} = make_rand_term_rand_size(10), % MUTATE!
    {Mutation, 0};
clone_and_mutate(Term, Cnt) when is_tuple(Term) ->
    {Clone,NewCnt} = clone_and_mutate(tuple_to_list(Term),Cnt),
    {my_list_to_tuple(Clone), NewCnt};
clone_and_mutate([Term|Tail], Cnt) ->
    {Car,Cnt1} = clone_and_mutate(Term,Cnt),
    {Cdr,Cnt2} = clone_and_mutate(Tail,Cnt1),
    {[Car | Cdr], Cnt2};
clone_and_mutate(Term, Cnt) ->
    {clone(Term), Cnt-1}.

clone(Term) ->
    binary_to_term(term_to_binary(Term)).

my_list_to_tuple(List) ->
    try list_to_tuple(List)
    catch
        error:badarg -> 
            %%io:format("my_list_to_tuple got badarg exception.\n"),
            list_to_tuple(purify_list(List))
    end.

purify_list(List) ->
    lists:reverse(purify_list(List, [])).
purify_list([], Acc) -> Acc;
purify_list([H|T], Acc) -> purify_list(T, [H|Acc]);
purify_list(Other, Acc) -> [Other|Acc].


%% Test the relational operators and internal BIFs on literals.
relop(Config) when is_list(Config) ->
    Big1 = -38374938373887374983978484,
    Big2 = 19738924729729787487784874,
    F1 = float(Big1),
    F2 = float(Big2),
    Bin = <<"abc">>,
    BitString = <<0:7>>,
    Map = #{a => b},
    EmptyMap = #{},
    Vs0 = [a,b,-33,-33.0,0,0.0,-0,0,42,42.0,Big1,Big2,F1,F2,
           Bin,BitString,Map,EmptyMap,[16#1234_5678_abcd]],
    Vs = [unvalue(V) || V <- Vs0],
    Ops = ['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
    binop(Ops, Vs).

%% Test the relational operators and internal BIFs on lists and tuples.
complex_relop(Config) when is_list(Config) ->
    Big = 99678557475484872464269855544643333,
    Float = float(Big),
    Bin = <<"abc">>,
    BitString = <<0:7>>,
    EmptyBitString = <<>>,
    Map = #{a => b},
    EmptyMap = #{},
    Vs0 = [an_atom,42.0,42,0.0,-0.0,Big,Float,Bin,BitString,
           EmptyBitString,Map,EmptyMap],
    Vs = flatmap(fun(X) -> [unvalue({X}),unvalue([X])] end, Vs0),
    Ops = ['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
    binop(Ops, Vs).

binop(Ops, Vs) ->
    Run = fun(Op, N) -> Cases = [{Op,V1,V2} || V1 <- Vs, V2 <- Vs],
                        run_test_module(Cases, true),
                        N + length(Cases) end,
    NumCases = foldl(Run, 0, Ops),
    {comment,integer_to_list(NumCases) ++ " cases"}.

run_test_module(Cases, GuardsOk) ->
    Es = [expr(C) || C <- Cases],
    Ok = unvalue(ok),
    Gts = case GuardsOk of
              true ->
                  Ges = [guard_expr(C) || C <- Cases],
                  lists:foldr(fun guard_test/2, [Ok], Ges);
              false ->
                  [Ok]
          end,
    Fun1 = make_function(guard_tests, Gts),
    Bts = lists:foldr(fun body_test/2, [Ok], Es),
    Fun2 = make_function(body_tests, Bts),
    Bbts = lists:foldr(fun internal_bif/2, [Ok], Es),
    Fun3 = make_function(bif_tests, Bbts),
    Id = {function,1,id,1,[{clause,1,[{var,1,'I'}],[],[{var,1,'I'}]}]},
    Module0 = make_module(op_tests, [Fun1,Fun2,Fun3,Id]),
    Module = erl_parse:new_anno(Module0),
    lists:foreach(fun(F) -> io:put_chars([erl_pp:form(F),"\n"]) end, Module),

    %% Compile, load, and run the generated module. Test both with and
    %% without compiler optimizations to ensure that we test both the
    %% implementation of the BIFs and the BEAM instructions.
    do_run_test_module(Module, []),
    do_run_test_module(Module, [no_copt,no_ssa_opt,no_postopt]).

do_run_test_module(Module, Opts) ->
    {ok,Mod,Code1} = compile:forms(Module, [time|Opts]),
    _ = code:delete(Mod),
    _ = code:purge(Mod),

    {module,Mod} = code:load_binary(Mod, Mod, Code1),

    run_function(Mod, guard_tests),
    run_function(Mod, body_tests),
    run_function(Mod, bif_tests),

    true = code:delete(Mod),
    _ = code:purge(Mod),

    ok.

expr({Op,X}) ->
    E = {op,1,Op,{call,1,{atom,1,id},[X]}},
    Res = eval([{op,1,Op,X}]),
    {E,{Op,X},Res};
expr({Op,X,Y}) ->
    E = {op,1,Op,{call,1,{atom,1,id},[X]},Y},
    Res = eval([{op,1,Op,X,Y}]),
    {E,{Op,value(X),value(Y)},Res}.

guard_expr({Op,X}) ->
    E = {op,1,Op,X},
    Res = eval([E]),
    {E,{Op,X},Res};
guard_expr({Op,X,Y}) ->
    E = {op,1,Op,X,Y},
    Res = eval([E]),
    {E,{Op,value(X),value(Y)},Res}.

run_function(Mod, Name) ->
    try Mod:Name() of
        _Other ->
            ok
    catch
        _:Reason ->
            io:format("~p", [get(last)]),
            ct:fail({'EXIT',Reason})
    end.

guard_test({E,Expr,Res}, Tail) ->
    True = unvalue(true),
    [save_term(Expr),
     {match,1,unvalue(Res),
      {'if',1,[{clause,1,[],[[E]],[True]},
               {clause,1,[],[[True]],[unvalue(false)]}]}}|Tail].

body_test({E,Expr,{'EXIT',_}}, Tail) ->
    [save_term(Expr),
     {match,1,{tuple,1,[unvalue('EXIT'), {var,1,'_'}]},
      {'catch',1,E}}|Tail];
body_test({E,Expr,Res}, Tail) ->
    [save_term(Expr),
     {match,1,unvalue(Res),E}|Tail].

internal_bif({{op,_,Op,X},Expr,Res}, Tail) ->
    internal_bif(Op, [X], Expr, Res, Tail);
internal_bif({{op,_,Op,X,Y},Expr,Res}, Tail) ->
    internal_bif(Op, [X,Y], Expr, Res, Tail).

internal_bif(Op, Args, Expr, {'EXIT',_}, Tail) ->
    [save_term(Expr),
     {match,1,{tuple,1,[unvalue('EXIT'), {var,1,'_'}]},
      {'catch',1,{call,1,{remote,1,{atom,1,erlang},unvalue(Op)},Args}}}|Tail];
internal_bif(Op, Args, Expr, Res, Tail) ->
    [save_term(Expr),
     {match,1,unvalue(Res),
      {call,1,{remote,1,{atom,1,erlang},unvalue(Op)},Args}}|Tail].

save_term(Term) ->
    {call,1,
     {atom,1,put},
     [{atom,1,last},unvalue(Term)]}.

make_module(Name, Funcs) ->
    [{attribute,1,module,Name},
     {attribute,0,compile,export_all} |
     Funcs ++ [{eof,0}]].

make_function(Name, Body) ->
    {function,1,Name,0,[{clause,1,[],[],Body}]}.

eval(E0) ->
    E = erl_parse:new_anno(E0),
    try erl_eval:exprs(E, []) of
        {value,Val,_Bs} -> Val
    catch
        throw:Reason -> Reason;
        exit:Reason -> {'EXIT',Reason};
        error:Reason:Stk -> {'EXIT',{Reason,Stk}}
    end.

unsafe_fusing(_Config) ->
    0 = usec_to_seconds(id(1)),
    234_567 = usec_to_seconds(id(1_234_567_890*1_000)),
    ok.

usec_to_seconds(Usec) when is_integer(Usec) ->
    %% The introduction of typed operands caused the loader
    %% to incorrectly fuse the following instrutions because
    %% the result register ({x,0}) from the 'div' instruction
    %% seemed to be distinct from both operands of the 'rem'
    %% instruction:
    %%
    %% {gc_bif,'div',
    %%         {f,0},
    %%         1,
    %%         [{tr,{x,0},{t_integer,any}},{integer,1000000}],
    %%         {x,0}}.
    %% {gc_bif,'rem',
    %%         {f,0},
    %%         1,
    %%         [{tr,{x,0},{t_integer,any}},{integer,1000000}],
    %%         {x,0}}.
    Sec = Usec div 1000000,
    Sec rem 1000000.

range_tests(_Config) ->
    %% Define the limits for smalls on a 64-bit system.
    {MinSmall, MaxSmall} = {-1 bsl 59, (1 bsl 59) - 1},
    case erlang:system_info(wordsize) of
        8 ->
            %% Assertions.
            2 = erts_debug:flat_size(MinSmall-1),
            0 = erts_debug:flat_size(MinSmall),
            0 = erts_debug:flat_size(MaxSmall),
            2 = erts_debug:flat_size(MaxSmall+1);
        4 ->
            ok
    end,

    lesser = range(-1 bsl 64),
    lesser = range(MinSmall),
    lesser = range(0),
    lesser = range(-1),
    lesser = range(0.9999),

    inside = range_any(1),
    inside = range_any(2),
    inside = range_any(2.5),
    inside = range_any(math:pi()),
    inside = range_any(5),
    inside = range_any(9),
    inside = range_any(10),

    greater = range(10.0001),
    greater = range(11),
    greater = range(MaxSmall),
    greater = range(1 bsl 64),
    greater = range(atom),
    greater = range(self()),
    greater = range(make_ref()),
    greater = range({a,b}),
    greater = range([a,b]),
    greater = range([]),
    greater = range(<<1,2,3>>),
    greater = range(fun() -> ok end),
    greater = range(fun ?MODULE:range_tests/1),

    lesser = range(-1 bsl 64),
    lesser = range(float(-1 bsl 64)),
    lesser = range_big(MinSmall - 2),
    lesser = range_barely_small(MinSmall - 1),

    inside = range_barely_small(MinSmall),
    inside = range_barely_small(-1 bsl 58),
    inside = range_barely_small(0),
    inside = range_barely_small(17.75),
    inside = range_barely_small(1 bsl 58),
    inside = range_barely_small(MaxSmall),

    greater = range_barely_small(MaxSmall + 1),
    greater = range_big(MaxSmall + 2),
    greater = range_big(1 bsl 64),
    greater = range_big(float(1 bsl 64)),

    lesser = range(-1 bsl 64),
    lesser = range(float(-1 bsl 64)),
    lesser = range_big(MinSmall - 2),

    inside = range_big(MinSmall),
    inside = range_big(-1 bsl 58),
    inside = range_big(0),
    inside = range_big(17.75),
    inside = range_big(1 bsl 58),
    inside = range_big(MaxSmall),

    greater = range_big(MaxSmall + 2),
    greater = range_big(1 bsl 64),
    greater = range_big(float(1 bsl 64)),

    inside = int_range_1(id(-100_000)),
    inside = int_range_1(id(-10)),
    inside = int_range_1(id(100)),
    inside = int_range_1(id(100_000)),

    outside = int_range_1(id(atom)),
    outside = int_range_1(id(-1 bsl 60)),
    outside = int_range_1(id(-100_001)),
    outside = int_range_1(id(100_001)),
    outside = int_range_1(id(1 bsl 60)),

    inside = int_range_2(id(1)),
    inside = int_range_2(id(42)),
    inside = int_range_2(id(16#f000_0000)),

    outside = int_range_2(id([a,list])),
    outside = int_range_2(id(0)),
    outside = int_range_1(id(-1 bsl 60)),
    outside = int_range_1(id(1 bsl 60)),

    inside = int_range_3(id(1 bsl 28)),
    inside = int_range_3(id((1 bsl 28) + 1)),
    inside = int_range_3(id((1 bsl 33) + 555)),
    inside = int_range_3(id((1 bsl 58) - 1)),
    inside = int_range_3(id(1 bsl 58)),

    outside = int_range_3(id({a,tuple})),
    outside = int_range_3(id(-1 bsl 60)),
    outside = int_range_3(id(-1000)),
    outside = int_range_3(id(100)),
    outside = int_range_3(id((1 bsl 58) + 1)),
    outside = int_range_3(id(1 bsl 60)),

    ok.

range(X) ->
    Res = range_any(X),
    if
        is_integer(X) ->
            Res = range_any(float(X)),
            Res = range_number(X),
            Res = range_number(float(X)),
            Res = range_int(X),
            if
                X =:= X band 16#ffff ->
                    Res = range_small_int(X);
                true ->
                    Res
            end;
        is_number(X) ->
            Res = range_number(X);
        true ->
            Res = range_big(X),
            Res = range_barely_small(X)
    end.

range_any(X0) ->
    X = id(X0),
    case range_any_1(X) of
        inside ->
            inside = range_any_2(X);
        Other ->
            outside = range_any_2(X),
            Other
    end.

%% The guard tests have different failure labels.
range_any_1(X) when 1 =< X, X =< 10 ->
    inside;
range_any_1(X) when X < 1 ->
    lesser;
range_any_1(X) when X > 10 ->
    greater.

%% The guard tests have the same failure label.
range_any_2(X) when 1 =< X, X =< 10 ->
    inside;
range_any_2(_) ->
    outside.

range_number(X) when is_number(X) ->
    case range_number_1(X) of
        inside ->
            inside = range_number_2(X);
        Other ->
            outside = range_number_2(X),
            Other
    end.

range_number_1(X) when 1 =< X, X =< 10 ->
    inside;
range_number_1(X) when X < 1 ->
    lesser;
range_number_1(X) when X > 10 ->
    greater.

range_number_2(X) when 1 =< X, X =< 10 ->
    inside;
range_number_2(_) ->
    outside.

range_int(X) when is_integer(X) ->
    case range_int_1(X) of
        inside ->
            inside = range_int_2(X);
        Other ->
            outside = range_int_2(X),
            Other
    end.

range_int_1(X) when 1 =< X, X =< 10 ->
    inside;
range_int_1(X) when X < 1 ->
    lesser;
range_int_1(X) when X > 10 ->
    greater.

range_int_2(X) when 1 =< X, X =< 10 ->
    inside;
range_int_2(_) ->
    outside.

range_small_int(X) when is_integer(X) ->
    case range_small_int_1(X) of
        inside ->
            inside = range_small_int_2(X);
        Other ->
            outside = range_small_int_2(X),
            Other
    end.

range_small_int_1(X) when 1 =< X, X =< 10 ->
    inside;
range_small_int_1(X) when X < 1 ->
    lesser;
range_small_int_1(X) when X > 10 ->
    greater.

range_small_int_2(X) when 1 =< X, X =< 10 ->
    inside;
range_small_int_2(_) ->
    outside.

range_barely_small(X) ->
    case range_barely_small_1(X) of
        inside ->
            inside = range_barely_small_2(X);
        Other ->
            outside = range_barely_small_2(X),
            Other
    end.

range_barely_small_1(X) when -1 bsl 59 =< X, X =< (1 bsl 59) - 1 ->
    inside;
range_barely_small_1(X) when X < -1 bsl 59 ->
    lesser;
range_barely_small_1(X) when X > (1 bsl 59) - 1 ->
    greater.

range_barely_small_2(X) when -1 bsl 59 =< X, X =< (1 bsl 59) - 1 ->
    inside;
range_barely_small_2(_) ->
    outside.

range_big(X) ->
    case range_big_1(X) of
        inside ->
            inside = range_big_2(X);
        Other ->
            outside = range_big_2(X),
            Other
    end.

range_big_1(X) when (-1 bsl 59) - 1 =< X, X =< 1 bsl 59 ->
    inside;
range_big_1(X) when X < (-1 bsl 59) - 1 ->
    lesser;
range_big_1(X) when X > 1 bsl 59 ->
    greater.

range_big_2(X) when (-1 bsl 59) - 1 =< X, X =< 1 bsl 59 ->
    inside;
range_big_2(_) ->
    outside.

int_range_1(X) when is_integer(X), -100_000 =< X, X =< 100_000 ->
    inside;
int_range_1(_) ->
    outside.

int_range_2(X) when is_integer(X), 1 =< X, X =< 16#f000_0000 ->
    inside;
int_range_2(_) ->
    outside.

int_range_3(X) when is_integer(X), 1 bsl 28 =< X, X =< 1 bsl 58 ->
    inside;
int_range_3(_) ->
    outside.

combined_relops(_Config) ->
    other = test_tok_char(-1 bsl 64),
    other = test_tok_char($A - 1),

    var = test_tok_char($A),
    var = test_tok_char($B),
    var = test_tok_char($P),
    var = test_tok_char($Y),
    var = test_tok_char($Z),

    other = test_tok_char($Z + 1),

    var = tok_char($_),
    other = tok_char(float($_)),

    other = test_tok_char(1 bsl 64),

    other = test_tok_char(atom),
    other = test_tok_char(self()),

    %%
    b = ge_ge_int_range_1(-200),
    b = ge_ge_int_range_1(-101),

    a = ge_ge_int_range_1(-100),
    a = ge_ge_int_range_1(-50),
    a = ge_ge_int_range_1(-10),

    b = ge_ge_int_range_1(-9),
    b = ge_ge_int_range_1(-6),

    a = ge_ge_int_range_1(-5),

    b = ge_ge_int_range_1(-4),
    b = ge_ge_int_range_1(0),
    b = ge_ge_int_range_1(42),

    %%
    b = ge_ge_int_range_2(-1 bsl 59),

    a = ge_ge_int_range_2((-1 bsl 59) + 1),
    a = ge_ge_int_range_2(-1 bsl 58),
    a = ge_ge_int_range_2(-1000),
    a = ge_ge_int_range_2(1 bsl 58),
    a = ge_ge_int_range_2((1 bsl 59) - 10),

    b = ge_ge_int_range_2((1 bsl 59) - 9),

    a = ge_ge_int_range_2((1 bsl 59) - 5),

    b = ge_ge_int_range_2((1 bsl 59) - 4),
    b = ge_ge_int_range_2((1 bsl 59) - 1),

    %%
    b = ge_ge_int_range_3(-1 bsl 59),

    b = ge_ge_int_range_3((-1 bsl 59) + 1),
    b = ge_ge_int_range_3(-1 bsl 58),
    b = ge_ge_int_range_3(-1000),
    b = ge_ge_int_range_3(1 bsl 58),

    a = ge_ge_int_range_3((1 bsl 59) - 20),
    a = ge_ge_int_range_3((1 bsl 59) - 15),
    a = ge_ge_int_range_3((1 bsl 59) - 10),

    b = ge_ge_int_range_3((1 bsl 59) - 9),

    a = ge_ge_int_range_3((1 bsl 59) - 5),

    b = ge_ge_int_range_3((1 bsl 59) - 4),
    b = ge_ge_int_range_3((1 bsl 59) - 1),

    %%
    b = ge_ge_int_range_4(-1 bsl 59),

    a = ge_ge_int_range_4((-1 bsl 59) + 1),
    a = ge_ge_int_range_4((-1 bsl 59) + 3),
    a = ge_ge_int_range_4((-1 bsl 59) + 5),

    b = ge_ge_int_range_4((-1 bsl 59) + 6),
    b = ge_ge_int_range_4((-1 bsl 59) + 9),

    a = ge_ge_int_range_4((-1 bsl 59) + 10),

    b = ge_ge_int_range_4((-1 bsl 59) + 11),

    b = ge_ge_int_range_4(0),
    b = ge_ge_int_range_4(1000),

    b = ge_ge_int_range_4((1 bsl 59) - 1),

    %% Test a sequence that can't occur in optimized code:
    %%   is_ge Fail Src 10
    %%   is_ge Fail Src 5
    Module = {?FUNCTION_NAME,[{test,1}],[],#{},
              [{function, test, 1, 2,
                [{label,1},
                 {line,[{location,"t.erl",4}]},
                 {func_info,{atom,?FUNCTION_NAME},{atom,test},1},
                 {label,2},
                 {test,is_ge,{f,4},
                  [{tr,{x,0},#beam_types:t_integer{elements={0,1000}}},
                   {integer,10}]},
                 {test,is_ge,
                  {f,3},
                  [{tr,{x,0},#beam_types:t_integer{elements={0,1000}}},
                   {integer,5}]},
                 {label,3},
                 {move,{atom,a},{x,0}},
                 return,
                 {label,4},
                 {move,{atom,b},{x,0}},
                 return]}],
              5},

    {ok,Mod,Code} = compile:forms(Module, [from_asm,time,report]),
    {module,Mod} = code:load_binary(Mod, Mod, Code),

    b = Mod:test(0),
    b = Mod:test(5),
    b = Mod:test(9),

    a = Mod:test(10),
    a = Mod:test(11),
    a = Mod:test(1000),

    true = code:delete(Mod),
    _ = code:purge(Mod),

    LargeMap = #{K => K || K <- lists:seq(1, 64)},
    Ref = make_ref(),
    [{}] = empty_map_or_nil(id({})),
    [{a,b}] = empty_map_or_nil(id({a,b})),
    [#{a := b}] = empty_map_or_nil(id(#{a => b})),
    [LargeMap] = empty_map_or_nil(id(LargeMap)),
    [Ref] = empty_map_or_nil(id(Ref)),
    [[a,b,c]] = empty_map_or_nil(id([a,b,c])),
    [a] = empty_map_or_nil(id(a)),
    [42] = empty_map_or_nil(id(42)),
    [] = empty_map_or_nil(id(#{})),
    [] = empty_map_or_nil(id([])),

    ok.

test_tok_char(C) ->
    Result = tok_char(C),
    if
        is_integer(C) ->
            Result = tok_char(float(C)),
            Result = tok_char_int(C),
            if
                C band 16#FFFF =:= C ->
                    Result = tok_char_int_range(C);
                true ->
                    Result
            end;
        true ->
            Result
    end.

%% is_ge + is_lt
tok_char(C) when $A =< C, C =< $Z ->
    var;
tok_char($_) ->
    var;
tok_char(_) ->
    other.

%% is_ge + is_ge
tok_char_int(C) when $A =< C, C =< $Z ->
    var;
tok_char_int($_) ->
    var;
tok_char_int(_) ->
    other.

%% is_ge + is_ge
tok_char_int_range(C) when $A =< C, C =< $Z ->
    var;
tok_char_int_range($_) ->
    var;
tok_char_int_range(_) ->
    other.

%% is_ge + is_ge
ge_ge_int_range_1(X) when -100 =< X, X =< -10 ->
    a;
ge_ge_int_range_1(-5) ->
    a;
ge_ge_int_range_1(_) ->
    b.

ge_ge_int_range_2(X) when (-1 bsl 59) + 1 =< X, X =< (1 bsl 59) - 10 ->
    a;
ge_ge_int_range_2((1 bsl 59) - 5) ->
    a;
ge_ge_int_range_2(_) ->
    b.

ge_ge_int_range_3(X) when (1 bsl 59) - 20 =< X, X =< (1 bsl 59) - 10 ->
    a;
ge_ge_int_range_3((1 bsl 59) - 5) ->
    a;
ge_ge_int_range_3(_) ->
    b.

ge_ge_int_range_4(X) when (-1 bsl 59) + 1 =< X, X =< (-1 bsl 59) + 5 ->
    a;
ge_ge_int_range_4((-1 bsl 59) + 10) ->
    a;
ge_ge_int_range_4(_) ->
    b.

%% GH-8325. An inverted test with an empty map would fail for
%% non-boxed terms.
empty_map_or_nil(V) when V =:= #{}; V =:= [] ->
    [];
empty_map_or_nil(V) ->
    [V].

%% Tests operators where type hints are significant.
typed_relop(Config) when is_list(Config) ->
    _ = [compare_integer_pid(1 bsl N) || N <- lists:seq(1, 64)],

    {error,<<7:3>>} = compare_bitstring({text, <<7:3>>, 0}),
    {error,<<0:8>>} = compare_bitstring({text, <<0:8>>, 0}),
    {error,<<0:9>>} = compare_bitstring({text, <<0:9>>, 0}),
    {text, 42} = compare_bitstring({text, <<0:3>>, 42}),

    {error,<<7:3>>} = compare_bitstring({binary, <<7:3>>, 0}),
    {error,<<0:8>>} = compare_bitstring({binary, <<0:8>>, 0}),
    {error,<<0:9>>} = compare_bitstring({binary, <<0:9>>, 0}),
    {binary, 42} = compare_bitstring({binary, <<0:3>>, 42}),

    negative = classify_value(id(-1 bsl 128)),
    other = classify_value(id(0)),
    other = classify_value(id(42)),
    other = classify_value(id(1 bsl 64)),
    other = classify_value(id(a)),

    ok.

compare_integer_pid(N) when is_integer(N) ->
    Immed = self(),
    true = is_pid(Immed),
    if
        N >= Immed -> ct:fail("integer compared greater than pid");
        N < Immed -> ok
    end.

%% GH-7433. Equality and non-equality tests with a bitstring could fail when it
%% should succeed and vice versa.
compare_bitstring({text, Res, _Data}) when is_bitstring(Res), Res =/= <<0:3>> ->
    {error, Res};
compare_bitstring({binary, Res, _Data}) when is_bitstring(Res), Res =/= <<0:3>> ->
    {error, Res};
compare_bitstring({binary, _Res, Data}) ->
    {binary, Data};
compare_bitstring({text, _Res, Data}) ->
    {text, Data}.

classify_value(N) when is_integer(N), N < 0 ->
    negative;
classify_value(_N) ->
    other.

term_equivalence(_Config) ->
    %% Term equivalence has been tested before in this suite, but we need to
    %% massage some edge cases that cannot easily be put into the other test
    %% cases.
    <<PosZero/float>> = id(<<0:1,0:63>>),
    <<NegZero/float>> = id(<<1:1,0:63>>),

    +0.0 = id(PosZero),
    -0.0 = id(NegZero),

    -1 = erts_internal:cmp_term(NegZero, PosZero),
    1 = erts_internal:cmp_term(PosZero, NegZero),

    -1 = cmp_float(NegZero, PosZero),
    1 = cmp_float(PosZero, NegZero),

    Floats = [0.0, -0.0, 4711.0, -4711.0, 12.0, 943.0],

    [true = (cmp_float(A, B) =:= erts_internal:cmp_term(A, B)) ||
     A <- Floats, B <- Floats],

    ok.

atom_ordering(_Config) ->
    Names = [[], [0], [$a,0,$b], "abc", "abc" ++ [0],
             "abc" ++ [1], "abc" ++ [2], "abcd", "abc" ++ [127],
             "abc" ++ [128], "abc" ++ [16#E9], "abc" ++ [16#100],
             "Elixir.Foo", "Elixir.Bar", "Elixir.Baz",
             lists:duplicate(63, $a) ++ [$b],
             lists:duplicate(64, $a),
             lists:duplicate(64, $a) ++ [$b],
             lists:duplicate(254, $a) ++ [$b],
             lists:duplicate(255, $a),
             lists:duplicate(254, 16#1F600) ++ [16#1F600],
             lists:duplicate(254, 16#1F600) ++ [16#1F601],
             [16#7F], [16#80], [16#E9], [16#100]],
    Atoms = [list_to_atom(Name) || Name <- Names],
    Ops = ['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],

    lists:foreach(
      fun(A) ->
              lists:foreach(
                fun(B) ->
                        Cmp = atom_name_order(atom_to_list(A),
                                              atom_to_list(B)),
                        Cmp = atom_order_guard(A, B),
                        check_relops(Ops, A, B, Cmp)
                end, Atoms)
      end, Atoms),

    NestedPairs = [{list_to_atom("abc"), list_to_atom("abc")},
                   {list_to_atom("abc"), list_to_atom("abc" ++ [0])},
                   {list_to_atom("abc" ++ [0]), list_to_atom("abc" ++ [1])},
                   {list_to_atom("Elixir.Bar"), list_to_atom("Elixir.Baz")},
                   {list_to_atom(lists:duplicate(64, $a)),
                    list_to_atom(lists:duplicate(64, $a) ++ [$b])},
                   {list_to_atom([16#7F]), list_to_atom([16#80])}],
    lists:foreach(fun check_nested_atom_order/1, NestedPairs),
    ok.

atom_name_order([], []) -> 0;
atom_name_order([], [_|_]) -> -1;
atom_name_order([_|_], []) -> 1;
atom_name_order([A|_], [B|_]) when A < B -> -1;
atom_name_order([A|_], [B|_]) when A > B -> 1;
atom_name_order([_|As], [_|Bs]) -> atom_name_order(As, Bs).

atom_order_guard(A, B) when A < B -> -1;
atom_order_guard(A, B) when A > B -> 1;
atom_order_guard(A, B) when A =:= B -> 0;
atom_order_guard(_, _) -> erlang:error(unordered_atoms).

check_nested_atom_order({A, B}) ->
    Cmp = atom_name_order(atom_to_list(A), atom_to_list(B)),
    Cmp = generic_term_order([A], [B]),
    Cmp = generic_term_order({A}, {B}),
    Cmp = generic_term_order(#{key => A}, #{key => B}),
    Cmp = generic_term_order(#{A => value}, #{B => value}),
    ok.

generic_term_order(A, B) when A < B -> -1;
generic_term_order(A, B) when A > B -> 1;
generic_term_order(A, B) when A =:= B -> 0;
generic_term_order(_, _) -> erlang:error(unordered_terms).

check_relops(Ops, A, B, Cmp) ->
    lists:foreach(
      fun(Op) ->
              Expected = expected_relop(Op, Cmp),
              Expected = apply(erlang, Op, [A, B])
      end, Ops).

expected_relop('==', Cmp) -> Cmp =:= 0;
expected_relop('/=', Cmp) -> Cmp =/= 0;
expected_relop('=:=', Cmp) -> Cmp =:= 0;
expected_relop('=/=', Cmp) -> Cmp =/= 0;
expected_relop('<', Cmp) -> Cmp < 0;
expected_relop('=<', Cmp) -> Cmp =< 0;
expected_relop('>', Cmp) -> Cmp > 0;
expected_relop('>=', Cmp) -> Cmp >= 0.

mixed_small_float(_Config) ->
    Two53 = 1 bsl 53,
    MaxSmall = (1 bsl 59) - 1,
    MinSmall = -(1 bsl 59),
    <<PosZero/float>> = <<0:1,0:63>>,
    <<NegZero/float>> = <<1:1,0:63>>,
    <<PosSubnormal/float>> = <<0:63,1:1>>,
    <<NegSubnormal/float>> = <<1:1,0:62,1:1>>,
    Pairs = [{Two53 + 1, float(Two53), 1},
             {Two53 - 1, float(Two53), -1},
             {-Two53 - 1, float(-Two53), -1},
             {-Two53 + 1, float(-Two53), 1},
             {Two53 + 1, float(Two53 + 2), -1},
             {-Two53 - 1, float(-Two53 - 2), 1},
             {MaxSmall, float(MaxSmall), -1},
             {MinSmall, float(MinSmall), 0},
             {MaxSmall, float(1 bsl 60), -1},
             {MinSmall, float(-(1 bsl 60)), 1},
             {42, 42.5, -1},
             {42, 41.5, 1},
             {0, PosSubnormal, -1},
             {0, NegSubnormal, 1},
             {0, PosZero, 0},
             {0, NegZero, 0},
             {1, 1.0, 0}],
    lists:foreach(fun check_mixed_small_float_pair/1, Pairs),
    ok.

check_mixed_small_float_pair({Small, Float, Expected}) ->
    Expected = mixed_small_float_guard(Small, Float),
    ReverseExpected = -Expected,
    ReverseExpected = mixed_small_float_guard(Float, Small),
    check_mixed_small_float_ops(Small, Float, Expected),
    check_mixed_small_float_ops(Float, Small, ReverseExpected),
    check_mixed_small_float_minmax(Small, Float, Expected),
    check_mixed_small_float_minmax(Float, Small, ReverseExpected).

mixed_small_float_guard(A, B) when A < B -> -1;
mixed_small_float_guard(A, B) when A > B -> 1;
mixed_small_float_guard(A, B) when A == B -> 0;
mixed_small_float_guard(_, _) -> erlang:error(unordered_numbers).

check_mixed_small_float_ops(A, B, Cmp) ->
    Ops = ['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
    lists:foreach(
      fun(Op) ->
              Expected = expected_mixed_small_float_op(Op, Cmp),
              Expected = apply(erlang, Op, [A, B])
      end, Ops).

expected_mixed_small_float_op('==', Cmp) -> Cmp =:= 0;
expected_mixed_small_float_op('/=', Cmp) -> Cmp =/= 0;
expected_mixed_small_float_op('=:=', _Cmp) -> false;
expected_mixed_small_float_op('=/=', _Cmp) -> true;
expected_mixed_small_float_op('<', Cmp) -> Cmp < 0;
expected_mixed_small_float_op('=<', Cmp) -> Cmp =< 0;
expected_mixed_small_float_op('>', Cmp) -> Cmp > 0;
expected_mixed_small_float_op('>=', Cmp) -> Cmp >= 0.

check_mixed_small_float_minmax(A, B, Cmp) ->
    Expected = case Cmp of
                   -1 -> {A, B};
                   0 -> {A, A};
                   1 -> {B, A}
               end,
    Expected = {erlang:min(A, B), erlang:max(A, B)}.

small_boxed_ordering(_Config) ->
    SmallBits = erlang:system_info(wordsize) * 8 - 4,
    MaxSmall = (1 bsl (SmallBits - 1)) - 1,
    MinSmall = -(1 bsl (SmallBits - 1)),
    Smalls = [MinSmall, MinSmall + 1, -1, 0, 1, MaxSmall - 1, MaxSmall],
    NegativeBigs = [MinSmall - 1, -(1 bsl 80)],
    PositiveBigs = [MaxSmall + 1, 1 bsl 80],
    NegativePairs = [{Small, Big, 1} || Small <- Smalls,
                                        Big <- NegativeBigs],
    PositivePairs = [{Small, Big, -1} || Small <- Smalls,
                                         Big <- PositiveBigs],
    lists:foreach(fun check_small_boxed_big_pair/1,
                  NegativePairs ++ PositivePairs),
    LocalFun = fun(X) -> X end,
    ExternalFun = fun erlang:length/1,
    Parent = binary:copy(<<42>>, 96),
    ParentSize = byte_size(Parent),
    true = ParentSize > 64,
    SubBinary = binary:part(Parent, 1, 65),
    65 = byte_size(SubBinary),
    ParentSize = binary:referenced_byte_size(SubBinary),
    BoxedTerms = [{}, {boxed}, #{}, #{key => value}, make_ref(),
                  <<1:1>>, Parent, SubBinary,
                  LocalFun, ExternalFun],
    lists:foreach(
      fun(Small) ->
              lists:foreach(
                fun(Boxed) -> check_small_boxed_term(Small, Boxed) end,
                BoxedTerms)
      end, Smalls),
    ok.

check_small_boxed_big_pair({Small, Big, Expected}) ->
    Expected = mixed_small_float_guard(Small, Big),
    ReverseExpected = -Expected,
    ReverseExpected = mixed_small_float_guard(Big, Small),
    check_mixed_small_float_ops(Small, Big, Expected),
    check_mixed_small_float_ops(Big, Small, ReverseExpected),
    check_mixed_small_float_minmax(Small, Big, Expected),
    check_mixed_small_float_minmax(Big, Small, ReverseExpected).

check_small_boxed_term(Small, Boxed) ->
    -1 = generic_term_order(Small, Boxed),
    1 = generic_term_order(Boxed, Small),
    check_mixed_small_float_ops(Small, Boxed, -1),
    check_mixed_small_float_ops(Boxed, Small, 1),
    check_mixed_small_float_minmax(Small, Boxed, -1),
    check_mixed_small_float_minmax(Boxed, Small, 1).

hamt_comparison_paths(_Config) ->
    lists:foreach(fun check_hamt_comparison_size/1, [33, 64, 65, 127]),
    ok.

check_hamt_comparison_size(Size) ->
    Keys = lists:seq(1, Size),
    ReverseKeys = lists:reverse(Keys),
    EqualA = maps:from_list([{K, K} || K <- Keys]),
    EqualB = maps:from_list([{K, K} || K <- ReverseKeys]),
    check_hamt_map_pair(EqualA, EqualB, 0, true),

    ValuesA = maps:from_list([{K, 0} || K <- Keys]),
    EarlyDiff = maps:from_list(
                  [{K, case K of 1 -> 1; _ -> 0 end} || K <- Keys]),
    LateDiff = maps:from_list(
                 [{K, case K of Size -> 1; _ -> 0 end} || K <- Keys]),
    check_hamt_map_pair(ValuesA, EarlyDiff, -1, false),
    check_hamt_map_pair(ValuesA, LateDiff, -1, false),
    EarlyGreater = maps:from_list(
                      [{K, case K of 1 -> 1; _ -> 0 end} || K <- Keys]),
    LateGreater = maps:from_list(
                    [{K, case K of Size -> 1; _ -> 0 end} || K <- Keys]),
    check_hamt_map_pair(EarlyGreater, LateGreater, 1, false),

    ShiftedKeys = lists:seq(2, Size + 1),
    DifferentKeys = maps:from_list([{K, K} || K <- ShiftedKeys]),
    check_hamt_map_pair(EqualA, DifferentKeys, -1, false),

    NumericEqual = maps:from_list(
                     [{K, case K of Size -> 0.0; _ -> 0 end} || K <- Keys]),
    check_hamt_map_pair(ValuesA, NumericEqual, 0, false),
    ok.

check_hamt_map_pair(A, B, ExpectedOrder, ExactEqual) ->
    ExpectedOrder = map_order_guard(A, B),
    ReverseExpectedOrder = -ExpectedOrder,
    ReverseExpectedOrder = map_order_guard(B, A),
    check_hamt_map_ops(A, B, ExpectedOrder, ExactEqual),
    check_hamt_map_ops(B, A, -ExpectedOrder, ExactEqual),
    Min = case ExpectedOrder of
              -1 -> A;
              0 -> A;
              1 -> B
          end,
    Max = case ExpectedOrder of
              -1 -> B;
              0 -> A;
              1 -> A
          end,
    Min = erlang:min(A, B),
    Max = erlang:max(A, B),
    case ExpectedOrder of
        0 ->
            true = erts_debug:same(erlang:min(A, B), A),
            true = erts_debug:same(erlang:max(A, B), A);
        _ ->
            ok
    end.

map_order_guard(A, B) when A < B -> -1;
map_order_guard(A, B) when A > B -> 1;
map_order_guard(A, B) when A == B -> 0;
map_order_guard(_, _) -> erlang:error(unordered_maps).

check_hamt_map_ops(A, B, Cmp, ExactEqual) ->
    Ops = ['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
    lists:foreach(
      fun(Op) ->
              Expected = expected_hamt_map_op(Op, Cmp, ExactEqual),
              Expected = apply(erlang, Op, [A, B])
      end, Ops).

expected_hamt_map_op('==', Cmp, _Exact) -> Cmp =:= 0;
expected_hamt_map_op('/=', Cmp, _Exact) -> Cmp =/= 0;
expected_hamt_map_op('=:=', _Cmp, Exact) -> Exact;
expected_hamt_map_op('=/=', _Cmp, Exact) -> not Exact;
expected_hamt_map_op('<', Cmp, _Exact) -> Cmp < 0;
expected_hamt_map_op('=<', Cmp, _Exact) -> Cmp =< 0;
expected_hamt_map_op('>', Cmp, _Exact) -> Cmp > 0;
expected_hamt_map_op('>=', Cmp, _Exact) -> Cmp >= 0.

cons_boxed_ordering(_Config) ->
    <<PosZero/float>> = <<0:1,0:63>>,
    <<NegZero/float>> = <<1:1,0:63>>,
    Parent = binary:copy(<<42>>, 96),
    ParentSize = byte_size(Parent),
    true = ParentSize > 64,
    SubBinary65 = binary:part(Parent, 1, 65),
    65 = byte_size(SubBinary65),
    ParentSize = binary:referenced_byte_size(SubBinary65),
    SubBinaries = [binary:part(Parent, Offset, Size)
                   || Offset <- [0, 1, 7], Size <- [63, 64, 65]],
    HeapBitstrings = [<<>>, <<1:1>>, <<1:7>>, <<1:8>>, <<1:9>>,
                      <<0:63>>, <<0:64>>, <<0:65>>],
    Bitstrings = HeapBitstrings ++ [Parent, SubBinary65] ++ SubBinaries,
    HamtMap = maps:from_list([{K, K} || K <- lists:seq(1, 33)]),
    LocalFun = fun(X) -> X end,
    ExternalFun = fun erlang:length/1,
    OtherBoxed = [PosZero, NegZero, 1.5, 1 bsl 80, -(1 bsl 80),
                  {}, {tuple}, #{}, #{a => b}, HamtMap, make_ref(),
                  LocalFun, ExternalFun],
    ConsTerms = [[1, 2, 3], [1, 2 | tail], [[1], 2]],
    lists:foreach(
      fun(Cons) ->
              lists:foreach(
                fun(Bitstring) ->
                        check_cons_boxed_pair(Cons, Bitstring, -1)
                end, Bitstrings),
              lists:foreach(
                fun(Boxed) ->
                        check_cons_boxed_pair(Cons, Boxed, 1)
                end, OtherBoxed)
      end, ConsTerms),
    ok.

check_cons_boxed_pair(Cons, Boxed, Expected) ->
    Expected = generic_term_order(Cons, Boxed),
    ReverseExpected = -Expected,
    ReverseExpected = generic_term_order(Boxed, Cons),
    check_relops(['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
                 Cons, Boxed, Expected),
    check_relops(['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
                 Boxed, Cons, ReverseExpected),
    check_mixed_small_float_minmax(Cons, Boxed, Expected),
    check_mixed_small_float_minmax(Boxed, Cons, ReverseExpected).

list_small_head_ordering(_Config) ->
    SmallBits = erlang:system_info(wordsize) * 8 - 4,
    MaxSmall = (1 bsl (SmallBits - 1)) - 1,
    MinSmall = -(1 bsl (SmallBits - 1)),
    SharedHead = {nested, [id(1), id(2)]},
    Pairs = [{[MinSmall | tail], [MinSmall + 1 | tail], -1},
             {[MinSmall | tail], [MaxSmall | tail], -1},
             {[MaxSmall - 1 | tail], [MaxSmall | tail], -1},
             {[-1 | z], [0 | a], -1},
             {[1, 2], [1, 3], -1},
             {[1 | 0], [1.0 | 1], -1},
             {[1 | 0], [1 | []], -1},
             {[1 | []], [1 | [2]], -1},
             {[SharedHead | alpha], [SharedHead | beta], -1},
             {[{a} | tail], [{b} | tail], -1},
             {[[a] | tail], [[b] | tail], -1},
             {[alpha, beta], [alpha, gamma], -1}],
    lists:foreach(fun check_list_small_head_pair/1, Pairs),

    SharedTail = [id(2), id(3)],
    SharedTailA = [id(17) | SharedTail],
    SharedTailB = [id(17) | SharedTail],
    false = erts_debug:same(SharedTailA, SharedTailB),
    check_list_small_head_pair({SharedTailA, SharedTailB, 0}),
    true = erts_debug:same(erlang:min(SharedTailA, SharedTailB),
                           SharedTailA),
    true = erts_debug:same(erlang:max(SharedTailA, SharedTailB),
                           SharedTailA),

    check_arithmetic_equal_list_tail([id(17) | 1], [id(17) | 1.0]),

    %% Separately allocated equal lists make min/max tie identity observable.
    EqualA = [id(17), id(tail)],
    EqualB = [id(17), id(tail)],
    0 = generic_term_order(EqualA, EqualB),
    0 = generic_term_order(EqualB, EqualA),
    check_relops(['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
                 EqualA, EqualB, 0),
    check_relops(['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
                 EqualB, EqualA, 0),
    true = erts_debug:same(erlang:min(EqualA, EqualB), EqualA),
    true = erts_debug:same(erlang:max(EqualA, EqualB), EqualA),
    true = erts_debug:same(erlang:min(EqualB, EqualA), EqualB),
    true = erts_debug:same(erlang:max(EqualB, EqualA), EqualB),
    ok.

check_list_small_head_pair({A, B, ExpectedOrder}) ->
    ExpectedOrder = generic_term_order(A, B),
    ReverseExpectedOrder = -ExpectedOrder,
    ReverseExpectedOrder = generic_term_order(B, A),
    Ops = ['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
    check_relops(Ops, A, B, ExpectedOrder),
    check_relops(Ops, B, A, ReverseExpectedOrder),
    check_mixed_small_float_minmax(A, B, ExpectedOrder),
    check_mixed_small_float_minmax(B, A, ReverseExpectedOrder).

check_arithmetic_equal_list_tail(A, B) ->
    0 = list_arithmetic_order_guard(A, B),
    0 = list_arithmetic_order_guard(B, A),
    Expected = [true, false, false, true, false, true, false, true],
    Ops = ['==', '/=', '=:=', '=/=', '<', '=<', '>', '>='],
    Expected = [apply(erlang, Op, [A, B]) || Op <- Ops],
    Expected = [apply(erlang, Op, [B, A]) || Op <- Ops],
    true = erts_debug:same(erlang:min(A, B), A),
    true = erts_debug:same(erlang:max(A, B), A),
    true = erts_debug:same(erlang:min(B, A), B),
    true = erts_debug:same(erlang:max(B, A), B).

list_arithmetic_order_guard(A, B) when A < B -> -1;
list_arithmetic_order_guard(A, B) when A > B -> 1;
list_arithmetic_order_guard(A, B) when A == B -> 0;
list_arithmetic_order_guard(_, _) -> erlang:error(unordered_lists).

cmp_float(A0, B0) ->
    A = float_comparable(A0),
    B = float_comparable(B0),
    if
        A < B -> -1;
        A > B -> +1;
        A =:= B -> 0
    end.

is_in_range(_Config) ->
    10.0 = is_in_range_1(id(10)),
    0.0 = is_in_range_1(id(0)),
    100.0 = is_in_range_1(id(100)),
    101 = is_in_range_2(id(100)),
    0 = is_in_range_2(id(0)),
    ok.

is_in_range_1(X) ->
    D = X band 16#FFFFFFFF,
    case D > 0 andalso D < 16#80000000 of
        true  -> D / 1;
        false -> 0.0
    end.

is_in_range_2(X) ->
    D = X band 16#FFFFFFFF,
    case D > 0 andalso D < 16#80000000 of
        true  -> D + 1;
        false -> 0
    end.

%% Converts a float to a number which, when compared with other such converted
%% floats, is ordered the same as '<' on the original inputs aside from the
%% fact that -0.0 < +0.0 as required by the term equivalence order.
%%
%% This has been proven correct with the SMT-LIB model below:
%%
%% (define-const SignBit_bv (_ BitVec 64) #x8000000000000000)
%% 
%% ; Two finite floats X and Y of unknown value
%% (declare-const X (_ FloatingPoint 11 53))
%% (declare-const Y (_ FloatingPoint 11 53))
%% (assert (= false (fp.isInfinite X) (fp.isInfinite Y)
%%            (fp.isNaN X) (fp.isNaN Y)))
%% 
%% ; ... the bit representations of the aforementioned floats. The Z3 floating-
%% ; point extension lacks a way to directly bit-cast a vector to a float, so
%% ; we rely on equivalence here.
%% (declare-const X_bv (_ BitVec 64))
%% (declare-const Y_bv (_ BitVec 64))
%% (assert (= ((_ to_fp 11 53) X_bv) X))
%% (assert (= ((_ to_fp 11 53) Y_bv) Y))
%% 
%% ; The bit hack we're going to test
%% (define-fun float_sortable ((value (_ BitVec 64))) (_ BitVec 64)
%% (ite (distinct (bvand value SignBit_bv) SignBit_bv)
%%  (bvxor value SignBit_bv)
%%  (bvnot value)))
%% 
%% (define-fun float_bv_lt ((LHS (_ BitVec 64))
%%                          (RHS (_ BitVec 64))) Bool
%%  (bvult (float_sortable LHS) (float_sortable RHS)))
%% 
%% (push 1)
%%   ; When either of X or Y are non-zero, (X < Y) = (bvX < bvY)
%%   (assert (not (and (fp.isZero X) (fp.isZero Y))))
%%   (assert (distinct (fp.lt X Y) (float_bv_lt X_bv Y_bv)))
%%   (check-sat) ; unsat, proving by negation that the above always holds
%% (pop 1)
%% 
%% (push 1)
%%   ; Negative zero should sort lower than positive zero
%%   (assert (and (fp.isNegative X) (fp.isPositive Y)
%%                (fp.isZero X) (fp.isZero Y)))
%%   (assert (not (float_bv_lt X_bv Y_bv)))
%%   (check-sat) ; unsat
%% (pop 1)
float_comparable(V0) ->
    Sign = 16#8000000000000000,
    Mask = 16#FFFFFFFFFFFFFFFF,
    <<V_bv:64/unsigned>> = <<V0/float>>,
    case V_bv band Sign of
        0 -> (V_bv bxor Sign) band Mask;
        Sign -> (bnot V_bv) band Mask
    end.

%%%
%%% Utilities.
%%%

unvalue(V) ->
    Abstr = erl_parse:abstract(V),
    erl_parse:anno_to_term(Abstr).

value({nil,_}) -> [];
value({integer,_,X}) -> X;
value({string,_,X}) -> X;
value({float,_,X})   -> X;
value({atom,_,X})    -> X;
value({tuple,_,Es}) ->
    list_to_tuple(lists:map(fun(X) -> value(X) end, Es));
value({cons,_,H,T}) ->
    [value(H) | value(T)];
value(Other) ->
    {value,Value,_} = erl_eval:expr(Other, erl_eval:new_bindings()),
    Value.

repeat(_, 0) -> ok;
repeat(Fun, N) ->
    Fun(),
    repeat(Fun, N-1).

id(I) -> I.
