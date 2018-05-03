-module(serv).
-export([start_server/0,initialize_ets/0,loop/1,init/1,
  terminate/2,sendMsg/2]).
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
  rmmems=[]
}).

init([]) ->
    initialize_ets(),
    start_server(), 
    {ok,true}.
genid(Room=#rooms{})->
  idgen!{self(),roomid,Room}.


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
    {From,roomid,Room}->
      io:format("received roomid generate req from ~p~n",[From]),
      From!{roomid,Room#rooms{rmid = RoomId+1}},
      loopid(RoomId+1)
  end.

loop(Data=#data{socket=Socket, id=Id}) ->
    receive
        {tcp,Socket,Bin} ->
             <<State:8,Str/binary>> = Bin,            
            case State of
                %login
                    0000 ->
                      io:format("received login msg~n"),
                            LId=binary_to_term(Str),
                            Regid="user"++integer_to_list(LId),
                            IdAtom=list_to_atom(Regid),
                            register(IdAtom,self()),
                            NewUser=#users{id=LId},
                            true=ets:insert(onlineusers,NewUser),
                            loop(Data#data{id=LId});
                           
                %chat
                    0001 ->
                      io:format("received chat msg~n"),
                            <<Sidsize:16,Sid:Sidsize/binary-unit:8,Tidsize:16,Tid:Tidsize/binary-unit:8,
                              Msg/binary>>=Str,
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
                      RmName = binary_to_term(Str),
                      genid(#rooms{rmmems =[Id],rmname = RmName}),
                      loop(Data);
                    %room join
                    0004->
                      io:format("received room join msg~n"),
                      <<SidSize:16,Sid:SidSize/binary,Rid/binary>> = Str,
                      SrcId=binary_to_term(Sid),
                      RmId=binary_to_term(Rid),
                      case ets:lookup(rooms,RmId) of
                        [Room]->
                          io:format("found room ~p~n",[Room]),
                          RoomMembs=Room#rooms.rmmems,
                          NewRoom=Room#rooms{rmmems =[SrcId|RoomMembs] },
                          true=ets:insert(rooms,NewRoom);
                        []->
                          io:format("room not found~n")
                      end,
                      loop(Data);
                    %room chat
                    0005->
                      io:format(("received room chat msg~n")),
                      <<Sidsize:16,_Sid:Sidsize/binary-unit:8,
                        Ridsize:16,Rid:Ridsize/binary-unit:8,_Body/binary>>=Str,
                      RmId=binary_to_term(Rid),
                      case ets:lookup(rooms,RmId) of
                        [Room]->
                          io:format("found room~p~n",[Room]),
                          RmMembs=Room#rooms.rmmems,
                          ok=sendMsg(RmMembs,Str);
                        []->
                          io:format("room not found~n")
                      end,
                      loop(Data);
                %logout
                    0002 ->
                      io:format("received logout msg~n"),
                      true=ets:delete(onlineusers,Id)
            end;

        {tcp_closed,Socket} ->
            io:format("Server socket closed~n"),
            true=ets:delete(onlineusers,Id);
        {privchat,Srcid,Msg}->
            Sid=term_to_binary(Srcid),
            M=term_to_binary(Msg),
            Packet = <<0006:8,(byte_size(Sid)):16,Sid/binary,M/binary>>,
            ok=gen_tcp:send(Socket,Packet),
            loop(Data);
        {roomchat,MsgBody}->
          Packet= <<0007:8,MsgBody/binary>>,
          ok=gen_tcp:send(Socket,Packet),
          loop(Data);
        {roomid,Room}->
          io:format("generate room id ~p~n",[Room#rooms.rmid]),
          true=ets:insert(rooms,Room),
          loop(Data)

    end.

sendMsg([],_Packet)->
  ok;
sendMsg([Head|Tail],Packet)->
      Pid=list_to_atom("user"++integer_to_list(Head)),
      Pid!{roomchat,Packet},
      sendMsg(Tail,Packet).
