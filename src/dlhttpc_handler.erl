%% coding: latin-1
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
%%%
%%% @author Fred Hebert <mononcqc@ferd.ca>
%%% @doc Dispcount worker implementation for TCP socket handling
%%% @end
%%%
-module(dlhttpc_handler).
-behaviour(dispcount).
-export([init/1, checkout/2, checkin/2, handle_info/2, dead/1, terminate/2, code_change/3]).

-record(state, {resource = {error,undefined},
                given = false,
                init_arg,
                ssl}).

init(Init) ->
    %% Make it lazy to connect. On checkout only!
    {ok, #state{init_arg=Init}}.

checkout(_From, State = #state{given=true}) ->
    {error, busy, State};
checkout(From, State = #state{resource={ok, Socket}, ssl=Ssl}) ->
    dlhttpc_sock:setopts(Socket, [{active,false}], Ssl),
    case dlhttpc_sock:controlling_process(Socket, From, Ssl) of
        ok ->
            {ok, {self(), Socket}, State#state{given=true}};
        {error, badarg} -> % caller died
            dlhttpc_sock:setopts(Socket, [{active, once}], Ssl),
            {error, caller_is_dead, State};
        {error, _Reason} -> % socket closed or something
            case reconnect(State) of
                {ok, NewState} ->
                    checkout(From, NewState);
                Return ->
                    Return
            end
    end;
checkout(From, State = #state{resource={error, _Reason}}) ->
    case reconnect(State) of
        {ok, NewState} ->
            checkout(From, NewState);
        Return ->
            Return
    end;
checkout(From, State) ->
    {stop, {invalid_call, From, State}, State}.

checkin(Socket, State = #state{resource={ok, Socket}, given=true, ssl=Ssl}) ->
    dlhttpc_sock:setopts(Socket, [{active, once}], Ssl),
    {ok, State#state{given=false}};
checkin(NewSocket, State = #state{given=true, ssl=Ssl}) ->
    dlhttpc_sock:setopts(NewSocket, [{active, once}], Ssl),
    %% The socket doesn't match the one we had -- an error happened somewhere
    %% But that's OK, we accept it.
    {ok, State#state{given=false, resource={ok, NewSocket}}}.

dead(State) ->
    %% aw shoot, someone lost our resource, we gotta create a new one:
    case reconnect(State#state{given=false}) of
        {ok, NewState} ->
            {ok, NewState};
        {error, _Reason, NewState} -> % stuff might be down!
            {ok, NewState}
    end.

handle_info(_Msg, State) ->
    %% something unexpected with the TCP connection if we set it to active,once???
    {ok, State}.

terminate(_Reason, _State) ->
    %% let the GC clean the socket.
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

reconnect(State = #state{init_arg={Host, Port, Ssl, Timeout, SockOpts}}) ->
    case dlhttpc_sock:connect(Host, Port, SockOpts, Timeout, Ssl) of
        {ok, Socket} ->
            {ok, State#state{resource = {ok, Socket}, ssl=Ssl}};
        {error, Reason} ->
            error_logger:warning_msg("dlhttpc reconnect fail (~p): ~p~n",[{Host,Port,Ssl}, Reason]),
            {error, Reason, State#state{resource = {error, Reason}, ssl=Ssl}}
    end.
