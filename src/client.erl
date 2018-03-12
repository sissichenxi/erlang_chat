-module(client).
-export([get_socket/0,client_login/1,send_message/1,logout/1]).

get_socket() ->
        {ok,Socket} = gen_tcp:connect("localhost",2345,[binary,{packet,4}]),
    register(client,spawn(fun() -> handle(Socket) end)).

client_login({Id}) ->
    client ! {self(),{login,Id}},
        receive
            {client, Response} ->
                ok
        end.

send_message({Id,Msg}) -> 
    client ! {self(),{msg,Id,Msg}},
        receive
            {client,Response} -> 
                ok
        end.

logout(Id) ->
    client ! {self(),{logout,Id}},
        receive
            {client,Response} -> ok
        end.

handle(Socket) ->
    receive
        {From,Request} ->
            io:format("client proc received Request ~p~n",[Request]),
            case Request of
                %login 0000
                {login,Id} ->
                    I = term_to_binary(Id),
                    Packet = <<0000:8,(byte_size(I)):16,I/binary>>,
                    ok=gen_tcp:send(Socket,Packet),               
                    
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
                    end,
                    handle(Socket);
                %chat 0001
                {msg,Id,Msg} ->
                    io:format("my message:~p~n",[Msg]),
                    Tid = term_to_binary(Id),
                    M = term_to_binary(Msg),
                    Packet = <<0001:8,(byte_size(Tid)):16,Tid/binary,(byte_size(M)):16,M/binary>>,
                    gen_tcp:send(Socket,Packet),
                        receive
                            {tcp,Socket,Bin} ->
                                <<_State:8,N/binary>> = Bin,
                                case binary_to_term(N) of
                                {ok,received} -> 
                                    From ! {"ok,you can send next message ~n"}
                                end
                        after 3000 ->
                            ok
                        end,
                        handle(Socket);
                %logout 0002
                {logout,Id} ->
                    I = term_to_binary({Id}),
                    Packet = <<0002:8,(byte_size(I)):16,I/binary>>,
                    gen_tcp:send(Socket,Packet),
                        receive
                            {tcp,Socket,Bin} ->
                                <<_State:4,N/binary>> = Bin,
                                case binary_to_term(N) of
                                    ok ->
                                        From ! {"ok,you have logout successfully ~n"}
                                end
                        after 5000 ->
                            ok
                        end,
                        gen_tcp:close(Socket)
            end
    end.