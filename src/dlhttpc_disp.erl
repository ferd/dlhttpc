%%% ----------------------------------------------------------------------------
%%% Copyright (c) 2012, Frederic Trottier-Hebert
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%%    * Redistributions of source code must retain the above copyright
%%%      notice, this list of conditions and the following disclaimer.
%%%    * Redistributions in binary form must reproduce the above copyright
%%%      notice, this list of conditions and the following disclaimer in the
%%%      documentation and/or other materials provided with the distribution.
%%%    * Neither the name of Erlang Training and Consulting Ltd. nor the
%%%      names of its contributors may be used to endorse or promote products
%%%      derived from this software without specific prior written permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY Erlang Training and Consulting Ltd. ''AS IS''
%%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%%% ARE DISCLAIMED. IN NO EVENT SHALL Erlang Training and Consulting Ltd. BE
%%% LIABLE SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
%%% BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
%%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
%%% OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
%%% ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%% ----------------------------------------------------------------------------

%%% @author Fred Hebert <mononcqc@ferd.ca>
%%% @doc Dispatcher for dlhttpc. Starts pools and handles checkin/checkout.
%%% The user shouldn't have to touch this module.
%%% @end
%%%
%% @todo: find a way to get rid of inactive pools.
%%   idea: each load balancer has an associated series of counters in an ETS
%%         table: one for checkin, one for checkout, and one timestamp.
%%         If the number of checkin is equal to the number of checkouts and the
%%         timestamp is outdated from a given value, it is assumed that the
%%         dispatcher pool has been inactive for that period of time. When
%%         that happens, it is shut down, to be reopened next time.
-module(dlhttpc_disp).
-export([checkout/6, checkin/1, checkin/2]).
-define(TABLE, ?MODULE).

checkout(Host, Port, Ssl, MaxConn, ConnTimeout, SocketOpts) ->
    Info = find_disp({Host, Port, Ssl}, {MaxConn, ConnTimeout, SocketOpts}),
    case dispcount:checkout(Info) of
        {ok, CheckinReference, {Owner,Socket}} ->
            {ok, {Info,CheckinReference,Owner,Ssl}, Socket};
        {error, Reason} ->
            {error, Reason}
    end.

checkin({Info, Ref, _Owner, _Ssl}) ->
    dispcount:checkin(Info, Ref, dead).

checkin({Info, Ref, Owner, Ssl}, Socket) ->
    case dlhttpc_sock:controlling_process(Socket, Owner, Ssl) of
        ok -> dispcount:checkin(Info, Ref, Socket);
        _ -> dispcount:checkin(Info, Ref, dead)
    end.

%%%%%%%%%%%%%%%
%%% Private %%%
%%%%%%%%%%%%%%%

%% This function needs to be revised after the shutdown mechanism
%% for a worker is decided on.
find_disp(Key, Args) ->
    case ets:lookup(?MODULE, Key) of
        [] ->
            start_disp(Key, Args);
        [{_,Info}] ->
            Info
    end.

%% Wart ahead. Atoms are created dynamically based on the key
%% to ensure uniqueness of pools.
%% TODO: optionally use gproc for registration to avoid this?
start_disp(Key = {Host, Port, Ssl}, Args = {MaxConn,ConnTimeout,SockOpts}) ->
    {ok, Type} = application:get_env(dlhttpc, restart),
    {ok, Timeout} = application:get_env(dlhttpc, shutdown),
    {ok, X} = application:get_env(dlhttpc, maxr),
    {ok, Y} = application:get_env(dlhttpc, maxt),
    AtomKey = case Ssl of
        true -> list_to_atom("dispcount_"++Host++integer_to_list(Port)++"_ssl");
        false -> list_to_atom("dispcount_"++Host++integer_to_list(Port))
    end,
    Res = dispcount:start_dispatch(
            AtomKey,
            {dlhttpc_handler, {Host,Port,Ssl,ConnTimeout,SockOpts}},
            [{restart,Type},{shutdown,Timeout},
             {maxr,X},{maxt,Y},{resources, MaxConn}]
            ),
    case Res of
        ok ->
            {ok, Info} = dispcount:dispatcher_info(AtomKey),
            ets:insert(?MODULE, {Key, Info}),
            Info;
        already_started ->
            find_disp(Key, Args)
    end.

