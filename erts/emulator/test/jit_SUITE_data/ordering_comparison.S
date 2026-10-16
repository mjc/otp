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

{exports, [{module_info,0},{module_info,1},{near_match,3},{run,3}]}.

{attributes, []}.

{labels, 16}.


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
