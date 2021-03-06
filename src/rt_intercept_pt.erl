%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 Basho Technologies, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(rt_intercept_pt).
-export([parse_transform/2]).

%% This parse transform looks for calls to rt_intercept:add/2, and if found
%% potentially modifies the second argument. The second argument can be a
%% list of intercept tuples or a single intercept tuple. An intercept tuple
%% can have either 2 or 3 elements, but either way, a final element of the
%% form
%%
%%   [{{F,Arity},{[var], fun()}}]
%%
%% is transformed into
%%
%%   [{{F,Arity},{[{varname, var}], tuple()}}]
%%
%% Only the second element of this tuple is modified. In the first form the
%% fun() is an anonymous interceptor function and [var] represents the list
%% of free variables used within the function but defined in the context in
%% which the function is defined. The list of vars is transformed into a
%% list of 2-tuples of var name and var, while the function is replaced
%% with its abstract format (which, since we are already dealing with
%% abstract format, is actually the abstract format of its abstract
%% format). If the final element of the argument tuple (or list of argument
%% tuples) is instead
%%
%%   [{{F,Arity}, fun()}]
%%
%% then the fun() is assumed to not use any free variables from the context
%% in which the function is defined. This is transformed to
%%
%%   [{{F,Arity},{[], tuple()}}]
%%
%% which is the same as the prior transformation but with an empty list of
%% free variables. A final element of any other form is left as is.

parse_transform(Forms, _) ->
    forms(Forms).

forms([F|Forms]) ->
    [form(F)|forms(Forms)];
forms(F) ->
    form(F).

form({function,LF,F,A,Clauses}) ->
    {function,LF,F,A,forms(Clauses)};
form({clause,L,H,G,B}) ->
    {clause,L,H,G,forms(B)};
form({match,L,Lhs,Rhs}) ->
    {match,L,forms(Lhs),forms(Rhs)};
form({call,L,{remote,_,{atom,_,rt_intercept},{atom,_,add}}=Fun,Args}) ->
    [Node, Intercept] = Args,
    {call,L,Fun,[Node,intercept(Intercept)]};
form(F) when is_tuple(F) ->
    list_to_tuple(forms(tuple_to_list(F)));
form(F) ->
    F.

intercept({tuple,L,[Mod,Intercepts]}) ->
    {tuple,L,[Mod,intercepts(Intercepts)]};
intercept({tuple,L,[Mod,ModInt,Intercepts]}) ->
    {tuple,L,[Mod,ModInt,intercepts(Intercepts)]}.

intercepts({cons,L1,{tuple,L2,[FA,Int]},T}) ->
    {cons,L1,{tuple,L2,[FA,intercepts(Int)]},intercepts(T)};
intercepts({tuple,L,[FreeVars,{'fun',LF,_}=Fun]}) ->
    {tuple,L,[freevars(FreeVars),erl_parse:abstract(Fun, LF)]};
intercepts({'fun',L,_}=Fun) ->
    {tuple,L,[{nil,L},erl_parse:abstract(Fun, L)]};
intercepts(F) ->
    F.

freevars({cons,L,H,T}) ->
    {cons,L,freevar(H),freevars(T)};
freevars({nil,_}=Nil) ->
    Nil.

freevar({var,L,V}=Var) ->
    {tuple,L,[{atom,L,V},Var]};
freevar(Term) ->
    Term.
