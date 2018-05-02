-module(client).
-export([login/1,send_message/2,send_roommsg/2,
  creat_room/1,join_room/1,logout/1]).
-record(data, {
  socket,
  id
}).

login({Id}) ->
    {ok,Socket} = gen_tcp:connect("localhost",2345,[binary,{packet,4}]),
    Pid=spawn(fun() -> handle(#data{socket = Socket}) end),
    register(?MODULE,Pid),
    ok=gen_tcp:controlling_process(Socket,Pid),
    ?MODULE ! {self(),{login,Id}}.

send_message(Id,Msg) ->
    io:format("send msg to ~p~n",[Id]),
    ?MODULE ! {self(),{chat,Id,Msg}}.

creat_room(RmName)->
    ?MODULE!{self(),{rmcreat,RmName}}.

join_room(RoomId)->
  ?MODULE!{self(),{joinrm,RoomId}}.

send_roommsg(RoomId,Msg)->
    ?MODULE!{self(),{rmchat,RoomId,Msg}}.

logout(Id) ->
        ?MODULE ! {self(),{logout,Id}}.

handle(Data=#data{socket = Socket,id=CId}) ->
    receive
        {tcp,Socket,Bin} ->
          io:format("received msg from server~p~n",[Bin]),
          <<State:8,Body/binary>> = Bin,
          case State of
            0004->
              <<Sidsize:16,Sid:Sidsize/binary-unit:8,
                Msgsize:16,Msg:Msgsize/binary-unit:8>>=Body,
              SId=binary_to_term(Sid),
              MSg=binary_to_term(Msg),
              io:format("user~p",[SId]),
              io:format(" says ~p~n",[MSg]);
            0005->
              <<Msgsize:16,Msg:Msgsize/binary-unit:8>>=Body,
              io:format("receive")
          end,
          %%gen_tcp:send(Socket,{chat_ok}),
          handle(Data);
        {tcp_closed,Socket}->
          io:format("tcp connection closed~n");
        {_From,Request} ->
            io:format("client proc received Request ~p~n",[Request]),
            case Request of
                %login 0000
                {login,Id} ->
                    I = term_to_binary(Id),
                    Packet = <<0000:8,(byte_size(I)):16,I/binary>>,
                    ok=gen_tcp:send(Socket,Packet),
                    handle(Data=#data{id = Id});
                %chat 0001
                {chat,Id,Msg} ->
                    io:format("my message:~p~n",[Msg]),
                    Sid=term_to_binary(CId),
                    Tid = term_to_binary(Id),
                    M = term_to_binary(Msg),
                    Packet = <<0001:8,(byte_size(Sid)):16,Sid/binary,(byte_size(Tid)):16,Tid/binary,(byte_size(M)):16,M/binary>>,
                    ok=gen_tcp:send(Socket,Packet),
                    handle(Data);
                %logout 0002
                {logout,Id} ->
                    I = term_to_binary(Id),
                    Packet = <<0002:8,(byte_size(I)):16,I/binary>>,
                    ok=gen_tcp:send(Socket,Packet),
                    gen_tcp:close(Socket);
                {rmcreat,Name}->
                    N=term_to_binary(Name),
                    Packet= <<0003:8,(byte_size(N)):16,N/binary>>,
                    ok= gen_tcp:send(Socket,Packet);
                {joinrm,RoomId}->
                  Rid=term_to_binary(RoomId),
                  Sid=term_to_binary(CId),
                  Packet= <<0004:8,(byte_size(Sid)):16,Sid/binary,(byte_size(Rid)):16,Rid/binary>>,
                  ok=gen_tcp:send(Socket,Packet);
                {rmchat,RoomId,Msg}->
                  Sid=term_to_binary(CId),
                  Rid=term_to_binary(RoomId),
                  M=term_to_binary(Msg),
                  Packet= <<0005:8,(byte_size(Sid)):16,Sid/binary,
                    (byte_size(Rid)):16,Rid/binary,(byte_size(M)):16,M/binary>>,
                  ok=gen_tcp:send(Socket,Packet);
                {_,_}->
                    io:format("wrong format cmd")
            end;
        M ->
          io:format("~p here~n", [M])
    end.


