%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 2021-2025. All Rights Reserved.
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

-module(jit_SUITE).

-export([suite/0, groups/0, all/0,
         init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2,
         init_per_testcase/2, end_per_testcase/2]).
-export([annotate/1, jmsingle/1, named_labels/1, ordering_comparison/1,
         ordering_comparison_near_match/1,
         ordering_comparison_registers/1,
         symbols/1, perfdirectory_set/1, perfdirectory_not_set/1]).

suite() ->
    [{timetrap, {minutes, 4}}].

groups() ->
    [{perf, [symbols, annotate, perfdirectory_set, perfdirectory_not_set]}].

all() ->
    [{group, perf}, jmsingle, named_labels, ordering_comparison,
     ordering_comparison_near_match, ordering_comparison_registers].

init_per_suite(Config) ->
    case erlang:system_info(emu_flavor) of
        jit ->
            Config;
        emu ->
            Config;
        _ ->
            {skip, "Tests require the JIT or interpreter emulator"}
    end.

end_per_suite(_Config) ->
    ok.

init_per_group(perf, Config) ->
    case erlang:system_info(emu_flavor) of
        jit ->
            init_performance_group(Config);
        _ ->
            {skip, "Performance tests require the JIT emulator"}
    end;
init_per_group(_, Config) ->
    Config.

init_performance_group(Config) ->
    case os:find_executable("perf") of
        false ->
            {skip, "perf not found"};
        _Perf ->
            PerfVsn = os:cmd("perf version"),
            case re:run(PerfVsn, "perf version (\\d+)\\.(\\d+)",
                        [{capture,all_but_first,list}]) of
                {match,[Major0,Minor0]} ->
                    Major = list_to_integer(Major0),
                    Minor = list_to_integer(Minor0),
                    if
                        Major > 5; Major =:= 5, Minor >= 11 ->
                            BuildIdDir = "--buildid-dir " ++
                                filename:join(
                                  proplists:get_value(priv_dir, Config),
                                  ".debug"),
                            DataFile = filename:join(
                                         proplists:get_value(priv_dir, Config),
                                         "init_test.data"),
                            Cmd = "perf " ++ BuildIdDir ++ " record -q -o " ++ DataFile ++ " ls",
                            os:cmd(Cmd),
                            Script = os:cmd("perf " ++ BuildIdDir ++ " script -i " ++ DataFile),
                            ct:log("~ts",[Script]),
                            case re:run(Script, "^\\W+ls",[multiline]) of
                                {match, _} ->
                                    [{sobefore,get_tmp_so_files()},
                                     {buildiddir,BuildIdDir}|Config];
                                nomatch ->
                                    {skip, "could not run `"++ Cmd ++"`"}
                            end;
                        true ->
                            {skip,"too old perf version: " ++ PerfVsn}
                    end;
                _ ->
                    {skip,"unknown old perf version: " ++ PerfVsn}
            end
    end.

end_per_group(perf, Config) ->
    %% perf inject writes data to /tmp and ~/.debug/tmp so we need to clean
    %% that up after the tests are done.
    SoToDelete = get_tmp_so_files() -- proplists:get_value(sobefore, Config),
    lists:foreach(
      fun(File) ->
              case file:delete(File) of
                  {error,eperm} ->
                      ok = file:del_dir_r(File);
                  ok ->
                      ok
              end
      end, SoToDelete),
    ok;
end_per_group(_, _Config) ->
    ok.

init_per_testcase(jmsingle, Config) ->
    case erlang:system_info(emu_flavor) of
        jit ->
            Config;
        _ ->
            {skip, "JIT-specific test"}
    end;
init_per_testcase(named_labels, Config) ->
    case erlang:system_info(emu_flavor) of
        jit ->
            %% Only run named_labels on platforms where we know it works.
            case erlang:system_info(system_architecture) of
                "x86" ++ _ ->
                    [{asmbefore,get_tmp_asm_files()}|Config];
                "aarch64" ++ _ ->
                    [{asmbefore,get_tmp_asm_files()}|Config];
                _ ->
                    {skip, "Unsupported architecture"}
            end;
        _ ->
            {skip, "JIT-specific test"}
    end;
init_per_testcase(_Case, Config) ->
    Config.

end_per_testcase(named_labels, Config) ->
    AsmToDelete = get_tmp_asm_files() -- proplists:get_value(asmbefore, Config),
    lists:foreach(
      fun(File) ->
              ok = file:delete(File)
      end, AsmToDelete),
    ok;
end_per_testcase(_, _Config) ->
    ok.

get_tmp_so_files() ->
    {ok, Home} = init:get_argument(home),
    filelib:wildcard("/tmp/jitted-*.so") ++
        filelib:wildcard(filename:join([Home,".debug","tmp","jitted-*.so"])).

symbols(Config) ->
    BuildIdDir = proplists:get_value(buildiddir, Config),
    DataFile = filename:join(
                 proplists:get_value(priv_dir, Config),
                 atom_to_list(?FUNCTION_NAME) ++ ".data"),
    os:cmd("perf "++ BuildIdDir ++" record -q -o " ++ DataFile ++ " " ++
           "erl +S 1 +JPperf true -noshell -eval '[lists:seq(1,10000) || _ <- lists:seq(1,1000)].' -s init stop"),
    Script = os:cmd("perf "++ BuildIdDir ++" script -i " ++ DataFile),
    case re:run(Script,"\\$lists:seq[^/]+/[0-9]",[global,{capture,first,list}]) of
        {match,Matches} ->
            ct:log("Found these symbols: ~p",[lists:usort(Matches)]),
            ok;
        nomatch ->
            ct:fail("Did not find lists:seq symbol in:~n~ts",[Script])
    end.
    
annotate(Config) ->
    BuildIdDir = proplists:get_value(buildiddir, Config),
    DataFile = filename:join(
                 proplists:get_value(priv_dir, Config),
                 atom_to_list(?FUNCTION_NAME) ++ ".data"),
    os:cmd("perf "++ BuildIdDir ++" record -k mono -q -o " ++ DataFile ++ " " ++
           "erl +S 1 +JPperf true -noshell -eval '[lists:seq(1,10000) || _ <- lists:seq(1,1000)].' -s init stop"),
    Script = os:cmd("perf "++ BuildIdDir ++" script -i " ++ DataFile),

    %% When doing "perf inject" the symbol of each function is changed
    %% from $lists:seq_loop/3 to lists:seq_loop/3. I don't know why that
    %% is, seems like a very odd bug in perf...
    {match, Symbols} = re:run(Script, "lists:seq[^/]+/[0-9]+",
                              [global,{capture,first,list}]),
    [[Symbol]|_] = lists:usort(Symbols),
    JitFile = DataFile ++ ".jit.data",
    "" = os:cmd("perf "++ BuildIdDir ++" inject --jit -i " ++ DataFile ++ " -o " ++ JitFile),
    Anno = os:cmd("perf "++ BuildIdDir ++" annotate --stdio -i " ++ JitFile ++ " " ++ Symbol ++ ""),
    case re:run(Anno,"Disassembly of section .text:") of
        {match,_} ->
            case re:run(Anno, "lists\\.erl:\\d+") of
                {match,_} ->
                    ok;
                nomatch ->
                    ct:fail("Did not find source line annotation for ~ts.~n~ts",
                            [Symbol, Anno])
            end;
        nomatch ->
            ct:fail("Did not find disassembly for ~ts.~n~ts",
                    [Symbol, Anno])
    end.

run_jmsingle_test(Param, ExpectSuccess, ErrorMsg) ->
    Cmd = "erl +JMsingle " ++ Param ++ " -noshell " ++
        "-eval \"erlang:display(all_is_well),erlang:halt(0).\"",
    Result = os:cmd(Cmd),
    SuccessfulEmulatorStart =
        case Result of
            "all_is_well" ++ _ ->
                true;
            _ ->
                Error = "Failed to allocate executable+writable memory",
                case string:find(Result, Error) of
                    nomatch -> false;
                    _ -> internal_error
                end
        end,
    case SuccessfulEmulatorStart of
        ExpectSuccess ->
            ok;
        _ ->
            ct:fail(ErrorMsg)
    end.

jmsingle(Config) ->
    %% Smoke test to check that the emulator starts with the +JMsingle
    %% true/false option and fails with a non-boolean, that is, we
    %% parse the command line correctly.
    case os:type() of
        {_, BSD} when BSD =:= netbsd;
                      BSD =:= openbsd ->
            %% +JMsingle true might not work on these platforms, and dump core
            %% because the emulator cannot be started.
            %% 
            %% Set the cwd to a temporary directory that we'll delete when the
            %% test is done.
            {ok, Cwd} = file:get_cwd(),
            TestDir = filename:join(proplists:get_value(priv_dir, Config),
                                    "jmsingle"),
            ok = file:make_dir(TestDir),
            try
                ok = file:set_cwd(TestDir),
                run_jmsingle_test("true", internal_error,
                                  "Emulator did not print the correct diagnostic "
                                  "(crashed?) with +JMsingle true")
            after
                file:set_cwd(Cwd),
                file:del_dir_r(TestDir)
            end;
        {_, _} ->
            run_jmsingle_test("true", true,
                              "Emulator did not start with +JMsingle true")
    end,
    run_jmsingle_test("false", true,
                      "Emulator did not start with +JMsingle false"),
    run_jmsingle_test("broken", false,
                      "Emulator started with bad +JMsingle parameter").

get_tmp_asm_files() ->
    {ok, Cwd} = file:get_cwd(),
    filelib:wildcard(filename:join(Cwd, "*.asm")).

named_labels(_Config) ->
    %% Check that pretty printing of named labels is working. We do
    %% that by loading this module in an emulator running with +JDdump
    %% true and then checking that the produced jit_SUITE.asm contains
    %% a label for each exported function. We also check that the
    %% label for the non-exported function get_tmp_asm_files/0, which
    %% is used by this test, is present.
    Exports = proplists:get_value(exports, ?MODULE:module_info()),
    ModName = atom_to_list(?MODULE),
    ModulePath = filename:dirname(code:which(?MODULE)),
    Cmd = "erl +JDdump true -noshell -pa " ++ ModulePath ++ " -eval \""
        ++ ModName ++ ":module_info(),erlang:halt(0).\"",
    os:cmd(Cmd),
    {ok, Cwd} = file:get_cwd(),
    AsmFile = filename:join(Cwd, ModName ++ ".asm"),
    {ok, Data} = file:read_file(AsmFile),
    Expected = sets:from_list([ lists:flatten(io_lib:format("~p/~p", [N,A]))
                                || {N,A} <- Exports]
                              ++ ["get_tmp_asm_files/0"]),
    StripSeqNo = fun(Lbl) ->
                         %% In the Arm JIT, labels have the form
                         %% @Mod:Name/Arity-SequenceNumber, so strip
                         %% out the Mod part and the sequence number
                         %% as we can't know anything about them.
                         case re:run(Lbl, "^.*\:(.*)-[0-9]*$",
                                     [{capture,all_but_first,list}]) of
                             {match,[R]} -> R;
                             nomatch -> Lbl
                         end
                 end,
    case re:run(Data, "^(.*)\:\n",
                [global,multiline,{capture,all_but_first,list}]) of
        {match,Labels} ->
            Found = sets:from_list([ StripSeqNo(NA) || [NA] <- Labels]),
            case sets:is_subset(Expected, Found) of
                true ->
                    ok;
                false ->
                    ct:fail("Expected ~p, found ~p",
                            [sets:to_list(Expected), sets:to_list(Found)])
            end;
        _ ->
            ct:fail("No labels found in assembly dump")
    end.

ordering_comparison(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    Mod = ?FUNCTION_NAME,
    File = filename:join(DataDir, "ordering_comparison"),
    {ok,Mod,Code} = compile:file(File, [from_asm,no_postopt,binary]),
    {module,Mod} = code:load_binary(Mod, File, Code),

    try
        One = {ordering,1},
        OneFloat = {ordering,1.0},
        One = Mod:run(One, padding, OneFloat),
        OneFloat = Mod:run(OneFloat, padding, One),

        EqualA = {ordering,[a,b]},
        EqualB = binary_to_term(term_to_binary(EqualA)),
        EqualA = Mod:run(EqualA, padding, EqualB),

        Prefix = lists:duplicate(256, prefix),
        LargeA = {ordering,Prefix ++ [a]},
        LargeB = {ordering,Prefix ++ [b]},
        LargeBcopy = binary_to_term(term_to_binary(LargeB)),
        LargeA = Mod:run(LargeA, padding, binary_to_term(term_to_binary(LargeA))),
        less = Mod:run(LargeA, padding, LargeB),
        greater = Mod:run(LargeBcopy, padding, LargeA),

        SmallBits = erlang:system_info(wordsize) * 8 - 5,
        SmallMin = -(1 bsl SmallBits),
        SmallMax = (1 bsl SmallBits) - 1,
        SmallMin = Mod:run(SmallMin, padding, SmallMin),
        less = Mod:run(SmallMin, padding, SmallMax),
        greater = Mod:run(SmallMax, padding, SmallMin),

        1 = Mod:run(1, padding, 1.0),
        PosZero = 0.0,
        NegZero = -0.0,
        PosZero = Mod:run(PosZero, padding, NegZero),
        NegZero = Mod:run(NegZero, padding, PosZero),

        less = Mod:run({ordering,1}, padding, {ordering,2}),
        greater = Mod:run({ordering,2}, padding, {ordering,1})
    after
        true = code:delete(Mod),
        false = code:purge(Mod)
    end,

    ok.

ordering_comparison_near_match(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    Mod = ordering_comparison,
    File = filename:join(DataDir, "ordering_comparison"),
    {ok,Mod,Code} = compile:file(File, [from_asm,no_postopt,binary]),
    {module,Mod} = code:load_binary(Mod, File, Code),

    try
        less = Mod:near_match({ordering,1}, padding, {ordering,2}),
        equal = Mod:near_match({ordering,1}, padding, {ordering,1.0}),
        greater = Mod:near_match({ordering,2}, padding, {ordering,1}),
        unexpected = Mod:near_match({ordering,1}, not_padding, {ordering,2}),

        less = Mod:near_changed(1, 0, 2),
        greater = Mod:near_changed(1, 0, 1),
        equal = Mod:near_changed(2, 2, 1),
        greater = Mod:near_changed_rhs(1, 1, 2),
        equal = Mod:near_same_order(2, padding, 1),
        less = Mod:near_same_order(1, padding, 2),
        less = Mod:near_intervening(1, padding, 2),
        greater = Mod:near_intervening(2, padding, 1),
        {intervening,1} = Mod:near_intervening(1, padding, 1)
    after
        true = code:delete(Mod),
        false = code:purge(Mod)
    end,

    ok.

ordering_comparison_registers(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    Mod = ordering_comparison,
    File = filename:join(DataDir, "ordering_comparison"),
    {ok,Mod,Code} = compile:file(File, [from_asm,no_postopt,binary]),
    {module,Mod} = code:load_binary(Mod, File, Code),

    try
        1 = Mod:run_xx(1, 1.0),
        less = Mod:run_xx(1, 2),
        greater = Mod:run_xx(2, 1),
        {tuple,source} = Mod:run_same_x({tuple,source}),

        1 = Mod:run_xy(1, 1.0),
        less = Mod:run_xy(1, 2),
        greater = Mod:run_xy(2, 1),

        1 = Mod:run_yx(1, 1.0),
        less = Mod:run_yx(1, 2),
        greater = Mod:run_yx(2, 1)
    after
        true = code:delete(Mod),
        false = code:purge(Mod)
    end,

    ok.

perfdirectory_set(_Config) ->
    %% Confirm that when +JPperfdirectory is set, the jit/perf files
    %% end up in the appropriate directory
    TempDir = string:strip(os:cmd("mktemp -d"), right, $\n),
    run_perfdirectory_test("+JPperfdirectory " ++ TempDir, TempDir).

perfdirectory_not_set(_Config) ->
    %% Confirm that when +JPperfdirectory is not set, the jit/perf files
    %% end up in /tmp
    run_perfdirectory_test("", "/tmp").

run_perfdirectory_test(AdditionalFlags, ExpectedDirectory) ->
    Cmd = "erl -noinput -eval 'io:format(\"~s~n\", [os:getpid()]).' -s init stop +JPperf true " ++ AdditionalFlags,
    ThePid = string:strip(os:cmd(Cmd), right, $\n),
    JitDumpFile = ExpectedDirectory ++ "/jit-" ++ ThePid ++ ".dump",
    PerfMapFile = ExpectedDirectory ++ "/perf-" ++ ThePid ++ ".map",
    case lists:all(fun filelib:is_file/1, [JitDumpFile, PerfMapFile]) of
        true ->
            ok;
        _ ->
            ct:fail("Expected ~s and ~s to exist", [JitDumpFile, PerfMapFile])
    end.
