-module(client).1
-export([client_login/1,send_message/1,logout/1]).
-record(id,{currentid}).

client_login({Id}) ->
    {ok,Socket} = gen_tcp:connect("localhost",2345,[binary,{packet,4}]),
    IdAtom=spawn_atom(Id),
    register(IdAtom,spawn(fun() -> handle(Socket) end)),
    %record current id
    Cid = #id{currentid = Id},
    _=Cid#id{},

    IdAtom ! {self(),{login,Id}},
        receive
            {IdAtom, _Response} ->
                ok
        after 3000->
            io:format("failed to login")
        end.

send_message({Id,Msg}) ->
    Crid=#id{},
    Cid=Crid#id.currentid,
    IdAtom=spawn_atom(Cid),
    IdAtom ! {self(),{msg,Id,Msg}},
        receive
            {IdAtom,_Response} ->
                ok
        after 3000->
            io:format("failed to send")
        end.

logout(Id) ->
    Crid=#id{},
    if Id==Crid#id.currentid ->
        IdAtom=spawn_atom(Id),
        IdAtom ! {self(),{logout,Id}},
        receive
            {client,Response} -> ok
        end
    end.
spawn_atom(Id)->
    Clientid="client"++integer_to_list(Id),
    list_to_atom(Clientid).

handle(Socket) ->
    receive
        {From,Request} ->
            io:format("client proc received Request ~p~n",[Request]),
            case Request of
                %login 0000
                {login,Id} ->
                    I = term_to_binary(Id),
                    Packet = <<0000:8,(byte_size(I)):16,I/binary>>,
                    gen_tcp:controlling_process(Socket,spawn(?MODULE,handle_tcpmsg,{From,Socket})),
                    ok=gen_tcp:send(Socket,Packet),
                    handle(Socket);
                %chat 0001
                {msg,Id,Msg} ->
                    io:format("my message:~p~n",[Msg]),
                    Tid = term_to_binary(Id),
                    M = term_to_binary(Msg),
                    Packet = <<0001:8,(byte_size(Tid)):16,Tid/binary,(byte_size(M)):16,M/binary>>,
                    gen_tcp:send(Socket,Packet),
                    handle(Socket);
                %logout 0002
                {logout,Id} ->
                    I = term_to_binary({Id}),
                    Packet = <<0002:8,(byte_size(I)):16,I/binary>>,
                    gen_tcp:send(Socket,Packet),
                    gen_tcp:close(Socket);
                {_,_}->
                    io:format("wrong format cmd")
            end
    end.

handle_tcpmsg(From,Socket)->
    receive
    %from server
        {tcp,Socket,Bin} ->
            <<_State:8,S/binary>> = Bin,
            case binary_to_term(S) of
                success ->
                    From ! {client, "you have login successfully"},
                    io:format("you have login successfully ~n");
                failed ->
                    From ! {"you have login failed,please try again"},
                    gen_tcp:close(Socket)
            end
    after 5000 ->
        ok
    end.
