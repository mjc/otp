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

{module, ordering_comparison}.  %% version = 0

{exports, [{module_info,0},{module_info,1},{near_changed,3},
           {near_changed_rhs,3},
           {near_intervening,3},{near_match,3},{near_same_order,3},
           {run,3},{run_same_x,1},{run_xx,2},{run_xy,2},{run_yx,2}]}.

{attributes, []}.

{labels, 58}.


{function, run, 3, 2}.
  {label,1}.
    {func_info,{atom,ordering_comparison},{atom,run},3}.
  {label,2}.
    {allocate,3,3}.
    {move,{x,0},{y,0}}.
    {move,{x,1},{y,1}}.
    {move,{x,2},{y,2}}.
    {call_ext,0,{extfunc,erlang,garbage_collect,0}}.
    %% Keep the comparisons adjacent; the equality path reads Y0 afterwards.
    {test,is_ge,{f,3},[{y,0},{y,2}]}.
    {test,is_ge,{f,4},[{y,2},{y,0}]}.
    {jump,{f,5}}.
  {label,3}.
    {move,{atom,less},{x,0}}.
    {deallocate,3}.
    return.
  {label,4}.
    {move,{atom,greater},{x,0}}.
    {deallocate,3}.
    return.
  {label,5}.
    {move,{y,0},{x,0}}.
    {deallocate,3}.
    return.


{function, module_info, 0, 7}.
  {label,6}.
    {func_info,{atom,ordering_comparison},{atom,module_info},0}.
  {label,7}.
    {move,{atom,ordering_comparison},{x,0}}.
    {call_ext_only,1,{extfunc,erlang,get_module_info,1}}.


{function, module_info, 1, 9}.
  {label,8}.
    {func_info,{atom,ordering_comparison},{atom,module_info},1}.
  {label,9}.
    {move,{x,0},{x,1}}.
    {move,{atom,ordering_comparison},{x,0}}.
    {call_ext_only,2,{extfunc,erlang,get_module_info,2}}.


{function, near_match, 3, 11}.
  {label,10}.
    {func_info,{atom,ordering_comparison},{atom,near_match},3}.
  {label,11}.
    {allocate,3,3}.
    {move,{x,0},{y,0}}.
    {move,{x,1},{y,1}}.
    {move,{x,2},{y,2}}.
    {test,is_eq_exact,{f,15},[{y,1},{atom,padding}]}.
    {test,is_ge,{f,12},[{y,0},{y,2}]}.
    {test,is_ge,{f,13},[{y,2},{y,0}]}.
    {jump,{f,14}}.
  {label,15}.
    {move,{atom,unexpected},{x,0}}.
    {deallocate,3}.
    return.
  {label,12}.
    {move,{atom,less},{x,0}}.
    {deallocate,3}.
    return.
  {label,13}.
    {move,{atom,greater},{x,0}}.
    {deallocate,3}.
    return.
  {label,14}.
    {move,{atom,equal},{x,0}}.
    {deallocate,3}.
    return.


{function, run_xx, 2, 17}.
  {label,16}.
    {func_info,{atom,ordering_comparison},{atom,run_xx},2}.
  {label,17}.
    {test,is_ge,{f,18},[{x,0},{x,1}]}.
    {test,is_ge,{f,19},[{x,1},{x,0}]}.
    {jump,{f,20}}.
  {label,18}.
    {move,{atom,less},{x,0}}.
    return.
  {label,19}.
    {move,{atom,greater},{x,0}}.
    return.
  {label,20}.
    return.


{function, run_same_x, 1, 22}.
  {label,21}.
    {func_info,{atom,ordering_comparison},{atom,run_same_x},1}.
  {label,22}.
    {test,is_ge,{f,23},[{x,0},{x,0}]}.
    {test,is_ge,{f,24},[{x,0},{x,0}]}.
    {jump,{f,25}}.
  {label,23}.
    {move,{atom,less},{x,0}}.
    return.
  {label,24}.
    {move,{atom,greater},{x,0}}.
    return.
  {label,25}.
    return.


{function, run_xy, 2, 27}.
  {label,26}.
    {func_info,{atom,ordering_comparison},{atom,run_xy},2}.
  {label,27}.
    {allocate,1,2}.
    {move,{x,1},{y,0}}.
    {test,is_ge,{f,28},[{x,0},{y,0}]}.
    {test,is_ge,{f,29},[{y,0},{x,0}]}.
    {jump,{f,30}}.
  {label,28}.
    {move,{atom,less},{x,0}}.
    {deallocate,1}.
    return.
  {label,29}.
    {move,{atom,greater},{x,0}}.
    {deallocate,1}.
    return.
  {label,30}.
    {deallocate,1}.
    return.


{function, run_yx, 2, 32}.
  {label,31}.
    {func_info,{atom,ordering_comparison},{atom,run_yx},2}.
  {label,32}.
    {allocate,1,2}.
    {move,{x,0},{y,0}}.
    {test,is_ge,{f,33},[{y,0},{x,1}]}.
    {test,is_ge,{f,34},[{x,1},{y,0}]}.
    {jump,{f,35}}.
  {label,33}.
    {move,{atom,less},{x,0}}.
    {deallocate,1}.
    return.
  {label,34}.
    {move,{atom,greater},{x,0}}.
    {deallocate,1}.
    return.
  {label,35}.
    {move,{y,0},{x,0}}.
    {deallocate,1}.
    return.


{function, near_changed, 3, 37}.
  {label,36}.
    {func_info,{atom,ordering_comparison},{atom,near_changed},3}.
  {label,37}.
    {allocate,3,3}.
    {move,{x,0},{y,0}}.
    {move,{x,1},{y,1}}.
    {move,{x,2},{y,2}}.
    {test,is_ge,{f,38},[{y,0},{y,2}]}.
    {test,is_ge,{f,39},[{y,1},{y,0}]}.
    {jump,{f,40}}.
  {label,38}.
    {move,{atom,less},{x,0}}.
    {deallocate,3}.
    return.
  {label,39}.
    {move,{atom,greater},{x,0}}.
    {deallocate,3}.
    return.
  {label,40}.
    {move,{atom,equal},{x,0}}.
    {deallocate,3}.
    return.


{function, near_same_order, 3, 43}.
  {label,42}.
    {func_info,{atom,ordering_comparison},{atom,near_same_order},3}.
  {label,43}.
    {allocate,3,3}.
    {move,{x,0},{y,0}}.
    {move,{x,1},{y,1}}.
    {move,{x,2},{y,2}}.
    {test,is_ge,{f,44},[{y,0},{y,2}]}.
    {test,is_ge,{f,45},[{y,0},{y,2}]}.
    {jump,{f,46}}.
  {label,44}.
    {move,{atom,less},{x,0}}.
    {deallocate,3}.
    return.
  {label,45}.
    {move,{atom,greater},{x,0}}.
    {deallocate,3}.
    return.
  {label,46}.
    {move,{atom,equal},{x,0}}.
    {deallocate,3}.
    return.


{function, near_intervening, 3, 49}.
  {label,48}.
    {func_info,{atom,ordering_comparison},{atom,near_intervening},3}.
  {label,49}.
    {allocate,3,3}.
    {move,{x,0},{y,0}}.
    {move,{x,1},{y,1}}.
    {move,{x,2},{y,2}}.
    {test,is_ge,{f,50},[{y,0},{y,2}]}.
    {test_heap,3,3}.
    {put_tuple2,{x,0},{list,[{atom,intervening},{y,0}]}}.
    {test,is_ge,{f,51},[{y,2},{y,0}]}.
    {jump,{f,52}}.
  {label,50}.
    {move,{atom,less},{x,0}}.
    {deallocate,3}.
    return.
  {label,51}.
    {move,{atom,greater},{x,0}}.
    {deallocate,3}.
    return.
  {label,52}.
    {deallocate,3}.
    return.


{function, near_changed_rhs, 3, 54}.
  {label,53}.
    {func_info,{atom,ordering_comparison},{atom,near_changed_rhs},3}.
  {label,54}.
    {test,is_ge,{f,55},[{x,0},{x,1}]}.
    {test,is_ge,{f,56},[{x,1},{x,2}]}.
    {jump,{f,57}}.
  {label,55}.
    {move,{atom,less},{x,0}}.
    return.
  {label,56}.
    {move,{atom,greater},{x,0}}.
    return.
  {label,57}.
    {move,{atom,equal},{x,0}}.
    return.
