ARM64 BEAM JIT and lowering gap audit
=====================================

Purpose
-------

This is the working tracker for AArch64 BeamAsm and BEAM lowering improvement
work. A candidate is not considered proven just because a handwritten `.S`
fixture reaches an emitter path. The proof has to show that normal Erlang
source still produces the work, that compiler/lowering/loader passes did not
already remove it, and that final AArch64 code still contains the gap.

The companion static checker is:

```
erts/emulator/beam/jit/arm/audit_arm64_jit_gaps.escript
```

It only proves facts visible in the checked-in source. It does not replace the
source-to-BEAM-to-JIT dump tests described below.

It also has an optional normal-source lowering probe mode:

```
erts/emulator/beam/jit/arm/audit_arm64_jit_gaps.escript --source-probes
```

That mode compiles small Erlang source fixtures with `to_asm` and reports
whether lowering still emits the candidate BEAM operations. It uses the
available host compiler, so a full OTP validation run should repeat the probes
with the repo-built compiler.

Current environment note
------------------------

The local instruction says to use `nix develop`, but this checkout currently
has no `flake.nix`, `shell.nix`, `default.nix`, or other `.nix` entrypoint.
Live build/test validation therefore needs either an external shell or OTP's
native bootstrap/configure flow.

Proof standard
--------------

Every optimization candidate should be moved through these gates:

1. Normal Erlang source fixture.
   Compile with `to_asm`, `beam_disasm:file/1`, or compiler listings and assert
   the target BEAM operation or missed lowering shape is present.

2. Loader/JIT dump from the same normal module.
   Load the module under `+JDdump true` and assert final AArch64 assembly still
   has the unwanted sequence or lacks the intended sequence.

3. Layer classification.
   Record whether the fix belongs in compiler lowering, loader op selection,
   ARM `ops.tab`, ARM emitter code, shared runtime helper code, or policy.

4. Optional `.S` fixture.
   Use `.S` only for emitter-only hazards or hard-to-generate safety cases.
   It must not be the only proof that the work is avoidable in real code.

5. Measurement.
   Benchmark only after the earlier gates prove the gap is real. Prefer
   realistic OTP/estone-style workloads, then focused microbenchmarks.

Cost model gate
---------------

The map experiments exposed a missing proof step. A candidate can be reachable
from normal source and still lose if the apparent missed optimization is not
where the real cost sits. Before patching, write down this model:

1. Existing selected path.
   Name the exact BEAM op, ARM op, and helper or fragment currently selected.
   Expand what the helper already does, including sub-helper calls.

2. Dominant runtime shapes.
   List the term/data shapes that route through the path. For maps this means
   flatmap versus HAMT, immediate key versus boxed key, body versus guard
   context, hit versus miss, and badmap/badkey behavior. For arithmetic this
   means small versus boxed, overflow, guard versus body, and type facts.

3. Removed work.
   Be specific: generic BIF dispatch, runtime crossing, hash calculation,
   header test, boxed/immediate test, register spill/fill, exception setup,
   branch, literal load, or helper call.

4. Added work.
   Count the new tests, branches, literal loads, helper calls, code bytes,
   register pressure, and duplicated shape checks. A precomputed fact is not a
   win if using it adds more hot-path work than it removes for the common shape.

5. Shape-sensitive decision.
   State whether the transform is universally profitable, representation
   specific, context specific, or only profitable with feedback/counters. If it
   is representation specific, prefer putting the split inside the shared helper
   that already owns the representation check instead of duplicating the check
   in each emitter.

6. Measurement design.
   Record raw samples plus `n`, min, median, average, standard deviation, and
   max. Use `+S 1` for focused microbenchmarks unless scheduler behavior is the
   thing being measured. Do not call a patch a performance win when only one of
   median or average improves and the effect is smaller than the noise.
   Raw sample lists can be summarized with:

   ```
   printf '%s\n' 224160 226559 225956 |
       erts/emulator/beam/jit/arm/audit_arm64_jit_gaps.escript --bench-stats
   ```

7. Acceptance rule.
   A commit needs one of these: clear code-size reduction with neutral runtime,
   or a runtime win where median and average both improve for the intended
   shape and no important sibling shape regresses beyond noise. Otherwise record
   the negative result and keep investigating.

Map experiment autopsy
----------------------

The literal `map_get/2` prehash idea is real but representation-sensitive:

* `map_get(a, M)` reaches `bif_map_get`; it is not removed by earlier lowering.
  `maps:get(a, M)` lowers to the same BIF shape, while `maps:get(a, M, Default)`
  lowers to `get_map_elements` plus default/error handling.
* ARM body `bif_map_get` already inlines map tests, badmap, and badkey behavior.
* The existing immediate-key helper already handles flatmaps cheaply and only
  computes a hash after it discovers a HAMT.
* Unconditionally loading a precomputed atom-key hash adds hot-path work for
  flatmaps. A module-emitter split duplicated header checks and also lost.
* A helper-local split avoids duplicated checks, but the measured median still
  did not beat the existing helper for the tested atom-key flatmap/HAMT shapes.
* Boxed literal keys were the profitable subcase because the existing body path
  called `get_map_element/2`, which recomputed the hash on HAMTs. Routing
  body-context boxed literal keys through `get_map_element_hash/3` preserves the
  same badkey/badmap handling and removes the runtime hash for HAMTs. Flatmaps
  are roughly neutral/noisy because their lookup is a linear `EQ` scan.

Source frequency snapshot from this checkout:

* `map_get`/`maps:get` textual call sites in `lib/` and `erts/`: 1,778.
* Direct `map_get(...)`: 293.
* `maps:get(...)`: 1,485.
* A simple literal/variable second-argument grep found 1,589 likely map-get
  shapes; this is a rough frequency hint, not a semantic parser.

Existing-path cost model:

| Shape | Existing path | Cost driver | Patch decision |
|-------|---------------|-------------|----------------|
| Body atom/small key, flatmap | `bif_map_get` -> `i_get_map_element_shared` -> flatmap scan | Already avoids runtime hash and runtime crossing | Leave unchanged |
| Body atom/small key, HAMT | `i_get_map_element_shared` computes hash only after HAMT check | Existing helper owns representation split | Leave unchanged; atom prehash was not robust |
| Body boxed literal key, flatmap | `get_map_element/2` runtime helper -> flatmap `EQ` scan | Runtime call remains; prehash is unused by flatmap | Accept only if sibling shape does not regress beyond noise |
| Body boxed literal key, HAMT | `get_map_element/2` recomputes `hashmap_make_hash(key)` | Runtime hash of literal key on every lookup | Use `get_map_element_hash/3` with loader-computed hash |
| Guard literal key | Existing `Fail != 0 && Key.isConstant()` path already passes precomputed hash | Already solved | Do not re-propose |

Reachability examples:

```erlang
%% Benefits on HAMTs: boxed literal key in body-context map_get/2.
benefits_erlang(M) ->
    map_get(<<"a">>, M).

%% Does not hit this patch: variable key.
no_literal_key_erlang(K, M) ->
    map_get(K, M).

%% Does not hit this patch: immediate atom key already uses the shared helper.
atom_key_erlang(M) ->
    map_get(a, M).

%% Does not hit this patch: default form lowers differently.
default_erlang(M) ->
    maps:get(<<"a">>, M, 0).

%% Does not hit this patch: pattern matching lowers to get_map_elements.
pattern_erlang(#{<<"a">> := V}) ->
    V.
```

```elixir
defmodule MapgetShapes do
  # Benefits on HAMTs: Elixir strings are boxed binary literals.
  def benefits_elixir(m), do: :erlang.map_get("a", m)

  # Does not hit this patch: variable key.
  def no_literal_key_elixir(k, m), do: :erlang.map_get(k, m)

  # Does not hit this patch: immediate atom key already uses the shared helper.
  def atom_key_elixir(m), do: :erlang.map_get(:a, m)

  # Does not hit this patch: still an Elixir Map.get/3 call at this stage.
  def default_elixir(m), do: Map.get(m, "a", 0)

  # Does not hit this patch: pattern matching lowers to get_map_elements.
  def pattern_elixir(%{"a" => v}), do: v
end
```

The BEAM assembly proof for both languages is the same: the benefiting shape
contains `{bif,map_get,{f,0},[{literal,<<"a">>},{x,0}],{x,0}}`; the variable
key shape uses `{x,0}` as the key, atom keys use `{atom,a}`, defaults compile to
`Map.get/3` or `get_map_elements`, and pattern matching uses `get_map_elements`.

The boxed-literal body-key patch was remeasured by comparing the parent commit
`c7e93d251f` against patched commit `020fefece2`, with separately built
`beam.jit` binaries, paired baseline/patched runs, `+S 1`, 30,000,000
iterations per target sample, and 20 pairs. The host was not pristine
(`load-before` was 6.78 and `load-after` was 5.05), so the result should be read
as noisy-host confirmation rather than a lab-grade run:

| Case | VM | Min us | Median us | Avg us | Stddev us | Max us |
|------|----|--------|-----------|--------|-----------|--------|
| Binary literal key, HAMT | Baseline | 918,434 | 943,284.0 | 991,617.0 | 212,254.0 | 1,889,812 |
| Binary literal key, HAMT | Patched | 630,836 | 658,505.0 | 665,406.7 | 27,716.0 | 720,398 |

That gives the target boxed-literal HAMT shape a 30.2% median improvement even
with the noisy baseline outlier. Control cases used 10,000,000 iterations and 10
paired samples:

| Control case | Baseline median us | Patched median us | Reading |
|--------------|--------------------|-------------------|---------|
| Binary literal key, flatmap | 195,574.5 | 190,711.5 | No comparable win; flatmaps do not use the hash |
| Atom literal key, HAMT | 136,193.5 | 136,917.5 | Neutral; immediate keys stay on the old helper |
| Binary variable key, HAMT | 329,506.5 | 341,685.5 | No win; key is not a loader-known literal |
| Binary literal key with default | 210,391.0 | 211,645.0 | Neutral; default form lowers differently |

Automated ways to shake out gaps
--------------------------------

Add these before relying on benchmarks:

* A Common Test helper that compiles normal Erlang fixture forms with
  `compile:forms(..., [return,to_asm])` or `compile:file(..., [to_asm,binary])`
  and matches BEAM ops before any JIT dump is checked.
* `list_bif_SUITE:source_lowering_proof/1` now carries the normal-source
  lowering check for unary plus, literal `map_get/2`, literal `is_map_key/2`,
  and a three-cons list chain.
* A JIT dump helper like the one in `list_bif_SUITE`, but fed from normally
  compiled modules rather than `from_asm` fixtures.
* Static parity reports comparing ARM and x86 `ops.tab`, `generators.tab`, and
  `BeamModuleAssembler::emit_*` coverage.
* A generated fixture corpus for small source patterns: literal map access,
  comparisons with immediates, list construction chains, binary construction,
  epilogues, and move groups.
* Code-size checks from JIT dumps for shared-fragment and cold-outlining work.
* A benchmark summarizer that reports raw samples, median, average, standard
  deviation, and max for baseline and patched runs.
* Allowlisted static checks for already-solved areas so old ideas do not return
  as "new" findings.

Migrated easy-win notes
-----------------------

The older `arm64_easy_wins.md` content has been folded into this tracker so
there is one place to update. Its original ladder was useful, but several items
have since been implemented or need stricter proof:

* List-test fusion for `is_nonempty_list` followed by `get_list`, `get_hd`, or
  `get_tl`: done. Keep only regression coverage and benchmarks.
* Runtime crossings with minimal `emit_enter_runtime` live-register counts:
  still useful, tracked through arithmetic/bitwise shared-fragment and BIF
  fallback candidates below.
* Paired load/store peepholes for consecutive X/Y traffic: partially done for
  pairs. Remaining work is triple/quad groups and register-backed XREG boundary
  proof.
* Straight-line success paths with cold slow paths: still useful, but only when
  JIT dumps prove real cold block placement and code-size wins.
* Type-driven fast paths from `BeamTypeId`: still useful, but only when the
  compiler/loader do not already carry the same shape fact.

The original benchmark target was the `list_bif_SUITE` fixed-list loop. Keep it
as a regression benchmark for completed list-test fusion, not as proof for new
lowering or emitter candidates.

Advanced audit rules carried forward:

* Prefer guarded shape specialization only when compiler, loader, and JIT dumps
  prove the shape fact is not already used.
* Reuse existing specialized instruction families before adding new ones.
* Pattern map extraction already lowers to `i_get_map_element_hash` with a
  precomputed literal-key hash; the remaining map gap is BIF-form literal-key
  access such as `map_get(a, M)`.
* Cold outlining must prove final layout improvement, not just move code into a
  helper while leaving hot-path branches unchanged.
* Macro-op fusion starts from concrete normal-source dumps, not handwritten
  `.S` fixtures alone.

Candidate tracker
-----------------

Status meanings:

* `Proven-static`: source audit shows a real implementation gap; still needs
  normal-source fixture proof before patching.
* `Needs-source-proof`: implementation looks narrow or missing, but source
  frequency and earlier lowering must be proven.
* `Needs-cost-model`: reachability is proven, but helper internals, runtime
  shapes, added work, and measurement design must be modeled before patching.
* `Representation-sensitive`: a transform may help one runtime shape and hurt
  another; it needs shape-specific dispatch or feedback.
* `Policy/advanced`: larger design inspired by other JITs; requires counters or
  VM policy work before implementation.
* `Downgraded`: investigated and found already solved earlier or not a primary
  performance gap.

| # | Area | Likely layer | Status | Evidence and next proof |
|---|------|--------------|--------|-------------------------|
| 1 | Unary `+X` / `splus/1` on ARM | ARM `ops.tab` / lowering | Burned down | Normal source `unary_plus(X) -> +X.` still lowers to unary plus BIF form; ARM now rewrites `splus/1` to `i_plus Fail Live Src i Dst`, matching the x86 identity-add shape. Repo-built ARM64 JIT dump changes `unary_plus/1` from `UBIF: '+'/1` to `i_plus_jIssd`. A 100,000,000-iteration microbenchmark improved from 499,863.5 us median to 321,752.0 us median, a 35.6% median speedup; the tiny function body grew from 323 bytes / 14 instruction-like lines to 432 bytes / 18 instruction-like lines. |
| 2 | `emit_is_eq` / `emit_is_ne` operand check | ARM emitter | Burned down | ARM now tests `X` and `Y` in the `always_one_of` condition instead of testing `X` twice. Needs generated-code proof for an asymmetric operand fixture before committing as a code-size win. |
| 3 | Equality-specific shared compare path | ARM emitter | Proven-static | x86 has `emit_arith_eq_shared`; ARM routes through `emit_arith_compare_shared`. Prove final assembly still calls the broader helper for `==`. |
| 4 | `/=` via equality-specific path | ARM emitter / lowering | Needs-source-proof | Depends on #3 and exact semantics. Add fixtures for integers, atoms, floats, lists, and boxed terms. |
| 5 | `is_lt` immediate-small fast path | ARM emitter | Needs-source-proof | ARM `is_ge` has immediate-small handling; `is_lt` should be checked with source guards such as `X < 42`. |
| 6 | `is_ge_ge` range checks | Lowering / ARM emitter | Needs-source-proof | ARM comments say non-known-small range checks use two comparisons. Prove normal range guards reach this form often enough. |
| 7 | Non-guard literal `map_get/2` prehash | ARM emitter / helper | Representation-sensitive | Normal `map_get/2` and `maps:get/2` reach `bif_map_get`. Atom/small-key prehashing is rejected because the existing helper already delays hashing until HAMT and flatmaps dominate the added work. Boxed literal body keys now use `get_map_element_hash/3`; binary-key HAMT median improved from 946,758.0 us to 627,153.5 us for 30,000,000 iterations (+S 1, n=10, 33.8% median speedup), while binary-key flatmap median moved from 575,600.0 us to 583,745.0 us and remains noise-sized relative to outliers/stddev. |
| 8 | Literal `is_map_key/2` prehash | ARM emitter | Burned down | Normal source `is_key(M) -> is_map_key(a, M).` still lowers to BIF form, but ARM now inlines untyped map checks instead of dispatching to the generic BIF and prehashes immediate literal keys through `i_get_map_element_hash_shared`. Repo-built ARM64 JIT dump changes `is_key/1` from `UBIF: is_map_key/2` to `inlined BIF is_map_key/2`. With `+S 1`, 20,000,000-iteration fixed-map microbenchmarks improved hit median from 244,272.5 us to 223,789.5 us and miss median from 251,828.0 us to 232,349.5 us. |
| 9 | Repeated literal map/tuple access sharing | Lowering | Needs-source-proof | Look for repeated `map_get(a, M)` / `element(N, T)` in one function and prove hash/index setup is duplicated after lowering. |
| 10 | Record/tuple field direct lowering | Lowering | Needs-source-proof | Only keep if normal record-style source emits generic tuple work not already lowered to direct tuple operations. |
| 11 | List construction chains beyond two conses | Lowering / ARM `ops.tab` | Proven-static | ARM has `put_list2` but no `put_list3+`; x86 has broader cons combining. Prove normal `[A,B,C|T]` reaches missed shapes. |
| 12 | Relax `put_list2` source constraints | ARM `ops.tab` | Needs-source-proof | Existing ARM rule is constrained to specific Y-head/same-destination shapes. Prove compiler emits nearby unfused variants. |
| 13 | Canonical epilogue lowering | Lowering / ARM `ops.tab` | Needs-source-proof | ARM has exact `move y==0 x==0 | deallocate u==1 | return`. Prove missed normal return shapes before adding fusions. |
| 14 | Multi-move `try_end` fusion | Lowering / ARM `ops.tab` | Needs-source-proof | ARM fuses only `try_end | move | deallocate`. Prove multi-move shapes survive lowering. |
| 15 | Triple/quad move pairing | ARM `ops.tab` / emitter | Proven-static | ARM has pair load/store rules only. Add normal-source fixtures that create adjacent memory-backed move groups. |
| 16 | XREG register/memory boundary pairing | ARM predicates / register cache | Proven-static | Pairing predicates exclude register-backed X registers with a hardcoded boundary. Needs spill/code-size counters. |
| 17 | Arithmetic guard shared fragments | ARM emitter | Proven-static | ARM arithmetic emitters use local runtime crossings; x86 has more shared guard-style paths. Measure code size first. |
| 18 | Bitwise guard shared fragments | ARM emitter | Proven-static | x86 has `emit_bitwise_fallback_guard`; ARM does not. Same-source bitwise folds are already done and excluded. |
| 19 | Inline common 2-byte UTF-8 construction | Lowering / ARM emitter | Needs-source-proof | ARM calls a shared helper for non-ASCII UTF-8. Prove common source produces 2-byte values and helper overhead is visible. |
| 20 | Fixed little-endian integer construction | Lowering / ARM emitter | Needs-source-proof | Binary construction still calls helpers for some fixed little-endian cases. Prove exact source shapes before patching. |
| 21 | Known zero-fill binary construction | Lowering / ARM emitter | Needs-source-proof | ARM has vectorized large known zero fill already. Only keep narrower missed-size cases proven by source fixtures. |
| 22 | Unknown-size zero fill | ARM emitter / CPU features | Proven-static | ARM `set_zero` has a byte-loop fallback and no DC ZVA/MOPS path. Needs feature detection and size thresholds. |
| 23 | Unaligned binary stores | ARM emitter | Proven-static | ARM unaligned store helper has byte-at-a-time loop. Prove normal bit-offset construction reaches it. |
| 24 | ARM CPU-feature dispatch in binary/arith paths | ARM emitter infrastructure | Proven-static | x86 emitters use CPU features heavily; ARM binary paths mostly do not. Start with MOPS/DC ZVA/LSE-relevant cases. |
| 25 | `select` jump-table threshold tuning | Lowering / ARM `ops.tab` policy | Proven-static | ARM uses fixed threshold `6`, matching x86. Add generated select fixtures and code-size/timing sweep. |
| 26 | Cold fallback outlining | ARM emitter / layout policy | Needs-source-proof | Existing note says this only helps with real cold placement. Add code-size and branch-layout dump checks. |
| 27 | BTI landing pads | ARM emitter hardening | Policy/advanced | asmjit supports ARM landing-pad concepts, but BeamAsm does not emit BTI. Treat as hardening, not speed. |
| 28 | PAC/pointer authentication | ARM emitter hardening | Policy/advanced | No BeamAsm PAC/ptrauth use found. Requires ABI/platform policy and correctness work. |
| 29 | Register-backed XREG count retuning | Register cache policy | Policy/advanced | ARM uses six register-backed X regs. Requires spill, code-size, and runtime counters before changing. |
| 30 | Static source-pattern generator | Test infrastructure | Proven-static | Needed to avoid benchmark-only discovery and `.S`-only false positives. |
| 31 | ARM/x86 parity report | Test infrastructure | Proven-static | Static differences already reveal `splus/1`, shared fragments, and CPU-feature gaps. |
| 32 | V8-style feedback-guided hot clones | JIT policy / lowering | Policy/advanced | Inspired by V8 Maglev/Sparkplug. Use BEAM counters and guard exits to existing generic code, not JS deopt. |
| 33 | V8-style inline-cache-like specialization | JIT policy / loader | Policy/advanced | Apply only to BEAM facts: stable call targets, tuple arity, map layout/literal keys, BIF paths. Do not invent JS hidden classes. |
| 34 | V8-style lazy metadata/code aging | JIT metadata / code policy | Policy/advanced | OTP already purges unloaded module code. New work would be cold generated-code policy and lazy optional metadata. |
| 35 | Veneer pending-stub cleanup | ARM module assembler | Needs-source-proof | Existing TODO is real, but classify as maintainability unless runtime evidence appears. |

Already solved or downgraded
----------------------------

Do not re-propose these without new evidence:

* List-test fusion for `is_nonempty_list` plus list access is already present.
* Guard BIF contiguous argument copy avoidance is already present.
* Paired-load guarding for overlapping ARM registers is already present.
* Same-source bitwise folds and same-source min/max folds are already present.
* Guard literal `map_get` prehashing has already been added; the remaining map
  gap is non-guard BIF-form lowering.
* Tuple construction already uses paired stores and repeated-value handling.
* Generic "binary reads" is too broad; ARM already has many optimized integer
  extraction paths.
* Apple MAP_JIT permission batching is downgraded because module codegen already
  defers executable protection until sealing.
* Module JIT purge exists; V8-style code aging would be a new cold-code policy,
  not basic missing purge support.

V8-inspired techniques
----------------------

These should be translated into BEAM terms rather than copied directly:

* Maglev-style mid-tier idea: fast guarded optimized clones for hot functions,
  with side exits to existing generic BeamAsm paths.
* Sparkplug-style idea: reuse existing BEAM/lowering facts and add lightweight
  counters/feedback instead of introducing a large IR first.
* Hidden-class analogy: specialize on tuple arity, map header/layout, literal
  key hash, stable call target, and binary shape facts. Do not introduce
  JavaScript-style hidden classes for Erlang terms.
* V8 Lite-style idea: lazy optional metadata, code aging, and feedback flushing,
  while respecting OTP's existing module purge semantics.

Next implementation slices
--------------------------

1. Add the normal-source fixture helper and convert one existing `.S`-only JIT
   dump test to the new two-stage source proof pattern.
2. Implement the lowest-risk correctness fix for the equality operand check if
   the asymmetric fixture confirms the typo.
3. Add source proof tests for `splus/1`, literal `map_get/2`, literal
   `is_map_key/2`, and `[A,B,C|T]`; these are the most concrete lowering/JIT
   candidates.
4. Add code-size reporting for shared-fragment candidates before changing ARM
   arithmetic or bitwise fallback layout.
