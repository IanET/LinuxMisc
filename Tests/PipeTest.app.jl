using Sockets

socket_path = "/tmp/pipe_test_service.sock"

@assert length(ARGS) == 1 "Usage: julia PipeTest.app.jl --server|--client"

if ARGS[1] == "--client"
    local client = connect(socket_path)
    println("Connected to server at $socket_path")
    for i in 1:5
        msg = "Hello from client! Message $i"
        write(client, "$msg\n")
        println("Sent to server: $msg")
        response = readline(client)
        println("Received from server: $response")
        sleep(1)
    end
    close(client)
elseif ARGS[1] == "--server"
    if ispath(socket_path); rm(socket_path) end
    server = listen(socket_path)
    println("Server listening on $socket_path")
    while true
        local client = accept(server)
        @async begin
            println("Client connected: $(client)")
            while !eof(client)
                msg = readline(client)
                println("Received from client: $msg")
                response = "OK"
                write(client, "$response\n")
                println("Sent to client: $response")
            end
            println("Client disconnected: $(client)")
            close(client)
        end
    end
else
    println("Usage: julia PipeTest.app.jl --server|--client")
end

