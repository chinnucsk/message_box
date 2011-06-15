%% File : user_watcher.erl
%% Description : user watcher process

-module(user_manager).
-include("user.hrl").
-export([init/0]).
-export([start/0, stop/0, start_all_users/0]).

start() ->
    register(?MODULE, spawn_link(?MODULE, init, [])).

init() ->
    process_flag(trap_exit, true),
    loop({0}).

start_all_users()->
    call(start_all_users, []).

stop() ->
    call(stop, [self()]).
    
%%
%% remote call functions.
%%

call(stop, Args)->
    ?MODULE ! {request, self(), stop, Args};

call(Name, Args)->
    Pid = whereis(?MODULE),
    Pid ! {request, self(), Name, Args},
    receive
	{Pid, reply, Result} -> Result
    after 30000 -> {error, timeout}
    end.

reply(To, Pid, Result)->
    To ! {Pid, reply, Result}.


loop({_Count}=State) ->
    Pid = self(),
    receive
	{request, From, stop, _Args} ->
	    handle_stop([From]);

	{request, From, Name, Args} ->
	    Result = handle_request(Name, Args),
	    reply(From, Pid, Result),
	    loop(State);

	{'EXIT', ExitPid, Reason} ->
	    io:format("~p: ~p is shutdown. Reason:~p~n", 
		      [?MODULE, ExitPid, Reason]),
	    loop(State);

	Other->
	    io:format("~p: unkown message received: ~p~n", [?MODULE, Other]),
	    reply(error, Pid, unknownMessage),
	    loop(State)
    end.

%%
%% server handlers.
%%

handle_request(start_all_users, []) ->
    Fun = fun(User) ->
		  io:format(".", []),
		  UserName = User#user.name,
		  m_user:start(UserName),
		  ok
	  end,
    user_db:map_do(Fun).

handle_stop([From]) ->
    io:format("~p stopped from ~p~n", [?MODULE, From]),
    exit(normal).
    

