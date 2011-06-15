%% File : message_db.erl
%% Description : database for user messages

-module(message_db).
-include("message.hrl").
-include("user.hrl").

-export([init/1]).
-export([start/1, stop/1,
	 save_message/2, get_message/1, get_message/2, get_latest_message/1,
	 get_sent_timeline/2]).

-export([get_sent_timeline_test/1]).

%%
%% @doc initial setup functions
%%

start(UserName)->
    spawn_link(?MODULE, init, [UserName]).

stop(Pid) ->
    Pid ! {stop, self()}.

init(UserName)->
    process_flag(trap_exit, true),
    Device = db_name(UserName),
    create_tables(Device),
    restore_table(Device),
    {ok, User} = user_db:lookup_name(UserName),
    loop(User).

create_tables(Device)->  
    ets:new(Device, [ordered_set, named_table, {keypos, #message.id}]),
    {DiscName, FileName} = dets_info(Device),
    dets:open_file(DiscName, [{file, FileName}, {keypos, #message.id}]).

close_tables(Device)->
    ets:delete(Device),
    {DiscName, _FileName} = dets_info(Device),
    dets:close(DiscName).

restore_table(Device)->
    Insert = fun(#message{id=_Id, text=_Text} = Message)->
		     ets:insert(Device, Message),
		     continue
	     end,
    {DiscName, _FileName} = dets_info(Device),
    dets:traverse(DiscName, Insert).

%%
%% @doc export functions
%%

save_message(Pid, Text)->
    call(Pid, save_message, [Text]).

get_message(Id)->
    {UserId, _Rest} = string:to_integer(string:substr(Id, 1, 8)),
    User = user_db:lookup_id(UserId),
    get_message(User#user.name, Id).

get_message(Pid, Id)->
    reference_call(Pid, get_message, [Id]).

get_sent_timeline(Pid, Count)->
    reference_call(Pid, get_sent_timeline, [Count]).

get_latest_message(Pid)->
    reference_call(Pid, get_latest_message, []).

%%
%% @doc remote call functions.
%%

call(Pid, Name, Args)->
    Pid ! {request, self(), Name, Args},
    receive
	{Pid, reply, Result} -> Result
    end.

reference_call(Pid, Name, Args)->
    Pid ! {ref_request, self(), Name, Args},
    receive
	{Pid, reply, Result} -> Result
    end.

reply(To, Pid, Result)->
    To ! {Pid, reply, Result}.

loop(User) ->
    UserName = User#user.name,
    Pid = self(),
    receive
	{ref_request, From, Name, Args} ->
	    spawn(fun()->
			  Result = handle_request(Name, [User | Args]),
			  reply(From, Pid, Result)
		  end),
	    loop(User);

	{request, From, Name, Args} ->
	    Result = handle_request(Name, [User | Args]),
	    reply(From, Pid, Result),
	    loop(User);
	{stop, From} ->
	    Device = db_name(UserName),
	    reply(From, Pid, close_tables(Device));

	{'EXIT', ExitPid, _Reason} ->
	    io:format("~p: user process(~p) is shutdown.~n", 
		      [?MODULE, ExitPid]),
	    Device = db_name(UserName),
	    close_tables(Device)
    end.

%%
%% @doc server handlers
%%

handle_request(save_message, [User, Text])->
    Id = get_max_id(User#user.name) - 1,
    MessageId = get_message_id(User#user.id, Id),
    Message = #message{id = Id, message_id = MessageId, text = Text},

    Device = db_name(User#user.name),
    {DiscName, _FileName} = dets_info(Device),
    ets:insert(Device, Message),
    dets:insert(DiscName, Message),
    {ok, MessageId};

handle_request(get_message, [User, MessageId])->
    MessagePattern = #message{id='$1', message_id=MessageId, text='$2'},
    Device = db_name(User#user.name),
    case ets:match(Device, MessagePattern) of
	[] -> {error, not_found};
	[[_Id, Text]] -> {ok, Text}
    end;

handle_request(get_sent_timeline, [User, Count])->
    Device = db_name(User#user.name),
    First = ets:first(Device),
    MessageIds = get_sent_timeline_ids(Device, Count, First, [First]),
    lists:map(fun(Id) -> [Msg] = ets:lookup(Device, Id), Msg end, MessageIds);

handle_request(get_latest_message, [User])->
    Device = db_name(User#user.name),
    case ets:first(Device) of
	'$end_of_table' -> {error, no_message_exist};
	Id -> 
	    [Message] = ets:lookup(Device, Id),
	    Message
    end.
	    
%%
%% @doc local functions.
%%

get_sent_timeline_ids(Device, Count, Before, Result)->
    if
	length(Result) >= Count -> lists:reverse(Result);
	true -> case ets:next(Device, Before) of
		    '$end_of_table' -> lists:reverse(Result);
		    Id -> get_sent_timeline_ids(Device, Count, Id, 
						   [Id | Result])
		end
    end.

dets_info(UserName)->
    DiscName = list_to_atom(atom_to_list(UserName) ++ "_Disk"),
    FileName = "/usr/local/message_box/db/" ++ atom_to_list(UserName),
    {DiscName, FileName}.

get_max_id(UserName)->
    Device = db_name(UserName),
    case ets:first(Device) of
	'$end_of_table' -> 0;
	First -> First
    end.

get_message_id(UserId, Id)->
    FormattedUserId = util:formatted_number(UserId, 9),
    FormattedId = util:formatted_number(abs(Id), 9),
    string:concat(FormattedUserId, FormattedId).

db_name(UserName)-> UserName.

%%
%% test
%%

get_sent_timeline_test(Count) ->
    user_db:start(),
    Pid = message_db:start(shin),
    Timeline = message_db:get_sent_timeline(Pid, Count),
    io:format("~p~n", [Timeline]),
    message_db:stop(Pid),
    user_db:stop().
