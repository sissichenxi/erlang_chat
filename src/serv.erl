-module(serv).
-export([start_server/0,initialize_ets/0,info_lookup/1,loop/1,info_update/3,init/1,terminate/2]).
-include("user_info.hrl").
-define(SERVER,?MODULE).

-record(state, {
    id
}).

start() ->
    gen_server:start_link({local,?SERVER},?MODULE,[],[]).

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
    loop({Socket, #state{}}).

initialize_ets() ->
    ets:new(test,[set,public,named_table,{keypos,#user.name}]).
    

info_lookup(Key) ->
    ets:lookup(test,Key).

info_update(Key,Pos,Update) ->
    ets:update_element(test,Key,{Pos,Update}).

loop({Socket,St}) ->
    receive
        {tcp,Socket,Bin} ->
             <<State:8,Str/binary>> = Bin,            
            case State of
                %login
                    0000 ->                      
                        <<Size:16,Body/binary>>=Str,  
                            %S = binary_to_term(Size),
                            Id=binary_to_term(Body),
                            Regid="user"++integer_to_list(Id),
                            IdAtom=list_to_atom(Regid),
                            %register(IdAtom,self()),
                            Suc = term_to_binary(sucess),                            
                            Packet = <<0000:8,(byte_size(Suc)):16,Suc/binary>>, 
                            ok=gen_tcp:send(Socket,Packet),
                            loop({Socket, St#state{id=Id}});
                           
                %chat
                    0001 ->
                            <<Idsize:16,Id:Idsize/binary-unit:8,Msgsize:16,Msg:Msgsize/binary-unit:8>>=Str,
                            N = term_to_binary({ok,received}),
                            Len = byte_size(N),
                            Packet = <<0001:8,Len:16,N/binary>>,
                            gen_tcp:send(Socket,Packet),
                            %转发给目标Pid
                            Regid="user"+integer_to_list(Id),
                            IdAtom=list_to_atom(Regid),
                            IdAtom!{Msg},
                            loop({Socket,State});
                %logout
                    0002 ->
                        %<<Idsize:16,Id:IdSize/binary-unit:8>>=Str,   
                        N = term_to_binary(ok),
                        Packet = <<0002:8,(byte_size(N)):16,N/binary>>,
                        gen_tcp:send(Socket,Packet)
            end;

        {tcp_closed,Socket} ->
                              io:format("Server socket closed~n");
        Msg->
            io:format("~p~n",Msg)
    end.