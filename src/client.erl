-module(client).
-export([client_login/1,send_message/1,logout/1]).
-record(id,{currentid}).

client_login({Id}) ->
    {ok,Socket} = gen_tcp:connect("localhost",2345,[binary,{packet,4}]),
    IdAtom=spawn_atom(Id),
    Pid=spawn(fun() -> handle(Id,Socket) end),
    register(IdAtom,Pid),
    ok=gen_tcp:controlling_process(Socket,Pid),
    IdAtom ! {self(),{login,Id}}.


send_message({Id,Msg}) ->
    IdAtom=spawn_atom(Id),
    IdAtom ! {self(),{chat,Id,Msg}}.

logout(Id) ->
        IdAtom=spawn_atom(Id),
        IdAtom ! {self(),{logout,Id}}.

spawn_atom(Id)->
    Clientid="client"++integer_to_list(Id),
    list_to_atom(Clientid).

handle(CId,Socket) ->
    receive
        {tcp,Socket,Bin} ->
          io:format("received msg from server~p~n",Bin),
          <<State:8,Body/binary>> = Bin,
          case State of
            0003->
              <<Size:16,Body:Size/binary-unit:8>>=Body,

          end,
          %%gen_tcp:send(Socket,{chat_ok}),
          handle(CId,Socket);
        {tcp_closed,Socket}->
          io:format("tcp connection closed~n");
        {From,Request} ->
            io:format("client proc received Request ~p~n",[Request]),
            case Request of
                %login 0000
                {login,Id} ->
                    I = term_to_binary(Id),
                    Packet = <<0000:8,(byte_size(I)):16,I/binary>>,
                    ok=gen_tcp:send(Socket,Packet),
                    handle(CId,Socket);
                %chat 0001
                {chat,Id,Msg} ->
                    io:format("my message:~p~n",[Msg]),
                    Sid=term_to_binary(CId),
                    Tid = term_to_binary(Id),
                    M = term_to_binary(Msg),
                    Packet = <<0001:8,(byte_size(Sid)):16,Sid/binary,(byte_size(Tid)):16,Tid/binary,(byte_size(M)):16,M/binary>>,
                    gen_tcp:send(Socket,Packet),
                    handle(CId,Socket);
                %logout 0002
                {logout,Id} ->
                    I = term_to_binary({Id}),
                    Packet = <<0002:8,(byte_size(I)):16,I/binary>>,
                    gen_tcp:send(Socket,Packet),
                    gen_tcp:close(Socket);
                {_,_}->
                    io:format("wrong format cmd")
            end;
        M ->
          io:format("~p here~n", [M])
    end.


