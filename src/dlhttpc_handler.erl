-module(dlhttpc_handler).
-behaviour(dispcount).
-export([init/1, checkout/2, checkin/2, handle_info/2, dead/1, terminate/2, code_change/3]).

-record(state, {resource = {error,undefined},
                given = false,
                init_arg,
                ssl}).

init(Init) ->
    %% Make it lazy to connect.
    %{ok, reconnect(#state{init_arg=Init})}.
    {ok, #state{init_arg=Init}}.

checkout(_From, State = #state{given=true}) ->
    {error, busy, State};
checkout(From, State = #state{resource={ok, Socket}, ssl=Ssl}) ->
    dlhttpc_sock:setopts(Socket, [{active,false}], Ssl),
    case gen_tcp:controlling_process(Socket, From) of
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
            %{ok, NewState} = reconnect(State),
            %checkout(From, NewState)
    end;
checkout(From, State = #state{resource={error, _Reason}}) ->
    case reconnect(State) of
        {ok, NewState} ->
            checkout(From, NewState);
        Return ->
            Return
    end;
    %{ok, NewState} = reconnect(State),
    %checkout(From, NewState);
checkout(From, State) ->
    {stop, {invalid_call, From, State}, State}.

checkin(Socket, State = #state{resource={ok, Socket}, given=true, ssl=Ssl}) ->
    dlhttpc_sock:setopts(Socket, [{active, once}], Ssl),
    {ok, State#state{given=false}};
checkin(_Socket, State) ->
    %% The socket doesn't match the one we had -- an error happened somewhere
    {ignore, State}.

dead(State) ->
    %% aw shoot, someone lost our resource, we gotta create a new one:
    case reconnect(State#state{given=false}) of
        {ok, NewState} ->
            {ok, NewState};
        {error, _Reason, NewState} -> % stuff might be down!
            {ok, NewState}
    end.
    %{ok, NewState} = reconnect(State),
    %{ok, NewState}.

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
            io:format("reconnect fail: ~p~n",[Reason]),
            {error, Reason, State#state{resource = {error, Reason}, ssl=Ssl}}
    end.
