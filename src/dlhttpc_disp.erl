%% Dispatcher for dlhttpc. Starts pools and handles checkin/checkout
%% TODO: find a way to get rid of inactive pools.
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

