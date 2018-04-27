-module(serv).
-export([start_server/0,initialize_ets/0,loop/1,init/1,terminate/2]).
-include("user_info.hrl").
-define(SERVER,?MODULE).

-record(users, {
    id
}).


init([]) ->
    initialize_ets(),
    start_server(), 
    {ok,true}.


terminate(_Reason,_State) -> ok.

start_server() ->
    {ok,Listen} = gen_tcp:listen(2345,[binary,{packet,4},{reuseaddr,true},{active,true}]),
    spawn(fun() -> handle_connect(Listen) end).

handle_connect(Listen) ->
    {ok,Socket} = gen_tcp:accept(Listen),
    spawn(fun() -> handle_connect(Listen) end),
    loop(Socket).

initialize_ets() ->
    ets:new(onlineusers,[set,public,named_table,{keypos,#users.id}]).

lookup_ets(Id)->
    ets:lookup(onlineusers,Id).

loop(Socket) ->
    receive
        {tcp,Socket,Bin} ->
             <<State:8,Str/binary>> = Bin,            
            case State of
                %login
                    0000 ->
                      io:format("received login msg~n"),
                        <<Size:16,Body:Size/binary-unit:8>>=Str,
                            Id=binary_to_term(Body),
                            Regid="user"++integer_to_list(Id),
                            IdAtom=list_to_atom(Regid),
                            register(IdAtom,self()),
                            NewUser=#users{id=Id},
                            ets:insert(onlineusers,NewUser),
                            loop(Socket);
                           
                %chat
                    0001 ->
                      io:format("received chat msg~n"),
                            <<Sidsize:16,Sid:Sidsize/binary-unit:8,Tidsize:16,Tid:Tidsize/binary-unit:8,
                              Msgsize:16,Msg:Msgsize/binary-unit:8>>=Str,
                            %send to tgt Pid
                            Regid="user"+integer_to_list(binary_to_term(Tid)),
                            case lookup_ets(binary_to_term(Tid)) of
                              [_Record]->
                                IdAtom=list_to_atom(Regid),
                                IdAtom!{binary_to_term(Sid),Msg};
                              []->
                                io:format("target user not online~n")
                            end,
                            loop(Socket);
                %logout
                    0002 ->
                      io:format("received logout msg~n")
                        %<<Idsize:16,Id:IdSize/binary-unit:8>>=Str,
            end;

        {tcp_closed,Socket} ->
                              io:format("Server socket closed~n");
        {Srcid,Msg}->
            io:format("receive msg from ~p :~p~n",Srcid,Msg),
            gen_tcp:send()
    end.