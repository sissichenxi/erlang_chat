-module(serv).
-export([start_server/0,initialize_ets/0,loop/1,init/1,
  terminate/2]).
-include("user_info.hrl").
-define(SERVER,?MODULE).

-record(users, {
    id
}).

-record(data, {
  socket,
  id
}).

-record(rooms,{
  rmid,
  rmname,
  rmmems
}).

init([]) ->
    initialize_ets(),
    start_server(), 
    {ok,true}.
genid(#rooms{rmid = RoomId})->
  idgen!{self(),roomid},
  receive
    {roomid,RoomId}->
      RoomId
  end,
  RoomId.

terminate(_Reason,_State) -> ok.

start_server() ->
    {ok,Listen} = gen_tcp:listen(2345,[binary,{packet,4},{reuseaddr,true},{active,true}]),
    spawn(fun() -> handle_connect(Listen) end),
    Pid=spawn(fun() ->loopid(0) end),
    register(idgen,Pid).

handle_connect(Listen) ->
    {ok,Socket} = gen_tcp:accept(Listen),
    spawn(fun() -> handle_connect(Listen) end),
    loop(#data{socket = Socket}).

initialize_ets() ->
    ets:new(onlineusers,[set,public,named_table,{keypos,#users.id}]),
    ets:new(rooms,[set,public,named_table,{keypos,#rooms.rmid}]).

lookup_ets(Id)->
    ets:lookup(onlineusers,Id).

loopid(RoomId)->
  receive
    {From,roomid}->
      From!{roomid,RoomId+1},
      loop(RoomId+1)
  end.

loop(Data=#data{socket=Socket, id=Id}) ->
    receive
        {tcp,Socket,Bin} ->
             <<State:8,Str/binary>> = Bin,            
            case State of
                %login
                    0000 ->
                      io:format("received login msg~n"),
                        <<Size:16,Body:Size/binary-unit:8>>=Str,
                            LId=binary_to_term(Body),
                            Regid="user"++integer_to_list(LId),
                            IdAtom=list_to_atom(Regid),
                            register(IdAtom,self()),
                            NewUser=#users{id=LId},
                            ets:insert(onlineusers,NewUser),
                            loop(Data#data{id=LId});
                           
                %chat
                    0001 ->
                      io:format("received chat msg~n"),
                            <<Sidsize:16,Sid:Sidsize/binary-unit:8,Tidsize:16,Tid:Tidsize/binary-unit:8,
                              Msgsize:16,Msg:Msgsize/binary-unit:8>>=Str,
                            %send to tgt Pid
                            Regid="user"++integer_to_list(binary_to_term(Tid)),
                            io:format("send msg to user ~p~n",[binary_to_term(Tid)]),
                            case lookup_ets(binary_to_term(Tid)) of
                              [Record]->
                                io:format("record found~p~n",[Record]),
                                IdAtom=list_to_atom(Regid),
                                IdAtom!{privchat,binary_to_term(Sid),binary_to_term(Msg)};
                              []->
                                io:format("target user not online~n")
                            end,
                            loop(Data);
                    %room creat
                    0003->
                      io:format("received room creat msg~n"),
                      <<Msgsize:16,RmName:Msgsize/binary>> = Str,
                      Roomid=genid(Room=#rooms{rmmems =Id,rmname = (binary_to_term(RmName)) }),
                      ets:insert(rooms,Room=#rooms{rmid = Roomid});
                    %room join
                    0004->
                      io:format("received room join msg~n");
                    %room chat
                    0005->
                      io:format(("received room chat msg~n")),
                      %<<Sidsize:16,Sid:Sidsize/binary-unit:8,Size:16,Body:Size/binary-unit:8>>=Str,
                      %Msg=binary_to_term(Body),
                      Key=ets:first(onlineusers),
                      sendMsg(Key,Str);
                %logout
                    0002 ->
                      io:format("received logout msg~n"),
                      true=ets:delete(onlineusers,Id)
            end;

        {tcp_closed,Socket} ->
            io:format("Server socket closed~n"),
            true=ets:delete(onlineusers,binary_to_term(Id));
        {privchat,Srcid,Msg}->
            Sid=term_to_binary(Srcid),
            M=term_to_binary(Msg),
            Packet = <<0004:8,(byte_size(Sid)):16,Sid/binary,(byte_size(M)):16,M/binary>>,
            ok=gen_tcp:send(Socket,Packet),
            loop(Data);
        {roomchat,MsgBody}->
          Packet= <<0005:8,MsgBody>>,
          ok=gen_tcp:send(Socket,Packet),
          loop(Data)
    end.
sendMsg(Key,Packet)->
  case lookup_ets(binary_to_term(Key)) of
    [Record]->
      io:format("record found~p~n",[Record]),
      Id=Record#users.id,
      Pid=list_to_atom("user"++integer_to_list(Id)),
      Pid!{roomchat,Packet},
      Next=ets:next(onlineusers,Key),
      sendMsg(Next,Packet);
    []->
      io:format("target user not online~n")
  end.

