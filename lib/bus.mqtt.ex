defmodule Bus.Mqtt do
	 import GenServer
	 require Logger 

	 alias Bus.Message
	 alias Bus.Protocol.Packet
	 alias Bus.IdProvider

   #if possible, add Id provider map here only in this state.
   #then it will be so independent of other process.
   @initial_state %{
        socket: nil, #to send & receive data
        timeout: 0,  #mqtt keep_alive timeout
        auto_reconnect: false, #reconnect auto,if disconnect.
        disconnected: true
   }

	  def start_link do
	    GenServer.start_link(__MODULE__,@initial_state,[name: __MODULE__])
	  end


    # connect to mqtt,
    # take params from config.
    def init(state) do
      if Application.get_env(:bus,:auto_connect, true) do
          case connect(:auto) do
               {:ok,socket,timeout,auto_reconnect} ->
                   {:ok,%{state | socket: socket,timeout: timeout, auto_reconnect: auto_reconnect, disconnected: false}}
               {:error, Reason} ->
                   {:ok,state}
          end
      else
          {:ok,state}
      end
    end
  
    def on_message_received(topic,asdf) do
        IO.inspect "New Message received."  
    end

    def on_error(errr) do
      IO.inspect "Error"
    end

    def on_disconnect(msg) do
      
    end

    def on_connect(msg) do
      
    end

    def on_info(msg) do
      
    end


    def connect() do
        GenServer.call(__MODULE__, {:connect})
    end

    #auto connect.
    def connect(:auto) do
                 host = Application.get_env(:bus, :host, 'localhost')
                 port = Application.get_env(:bus, :port, 1883)
                 client_id = Application.get_env(:bus, :client_id, 1)
                 username = Application.get_env(:bus, :username, "")
                 password = Application.get_env(:bus, :password, "")
                 will_topic = ""
                 will_message = ""
                 will_qos = 0
                 will_retain = 0
                 clean_session = 1
                 keep_alive = Application.get_env(:bus, :keep_alive, 120) #sec
                 auto_reconnect = Application.get_env(:bus, :auto_reconnect, false)

                 message = Message.connect(client_id, username, password,
                                  will_topic, will_message, will_qos,
                                  will_retain, clean_session, keep_alive)

                 timeout = get_timeout(keep_alive)

                 tcp_opts = [:binary, active: :once]
                 tcp_time_out = 10_000 #milliseconds

                 case :gen_tcp.connect(host, port, tcp_opts,tcp_time_out) do
                    {:ok, socket}    ->
                        :gen_tcp.send(socket,Packet.encode(message))
                        Application.get_env(:bus, :callback).on_connect("Connection successful")
                        {:ok, socket,timeout,auto_reconnect}
                    {:error, :econnrefused} ->
                        Application.get_env(:bus, :callback).on_error("can't reach server.")
                        {:error,"could not reach to server."}
                    {:error, :enetunreach} -> #bcz cline internet is not there.
                        Application.get_env(:bus, :callback).on_error("check your internet connection, can't reach server.")
                        {:error,"could not reach to server,check internet."}
                    {:error, reason} ->
                        Application.get_env(:bus, :callback).on_error(reason)
                        {:error,reason}
                  end
    end

    def handle_call({:connect,opts},_From,state) do
        case connect(:auto) do
               {:ok,socket,timeout,auto_reconnect} ->
                   IO.inspect "MQTT Connected."
                   {:ok,%{state | socket: socket,timeout: timeout, auto_reconnect: auto_reconnect, disconnected: false}}
                _ ->
                   {:ok,state}
          end
    end


	  def disconnect() do
	  	GenServer.cast( __MODULE__ , :disconnect)
	  end

	  def publish(topic,message,funn,qos \\ 1, dup \\ 0,retain \\ 0) do
	  	opts = %{
	  		topic: topic,
	  		message: message,
	  		dup: dup,
	  		qos: qos,
	  		retain: retain,
        cb: funn
	  	}
	  	GenServer.cast( __MODULE__ , { :publish , opts })
	  end

	  # list_of_data = [{topic,qos},{topic,qos}]
	  def subscribe(topics,qoses, funn) do
	  	GenServer.cast( __MODULE__ , { :subscribe , topics,qoses, funn})
	  end

    #check if arg is list or not.
	  def unsubscribe(list_of_topics, funn) do
	  	GenServer.cast( __MODULE__ , { :unsubscribe , list_of_topics, funn})
	  end

	  def pingreq do
	  	GenServer.cast( __MODULE__ , :ping)
	  end


  	 #define How to get ID. may be we need one process to manage ids, or Agent.
  	 #think and implement.
  	 def handle_cast({:publish, opts},%{socket: socket, timeout: timeout} = state) do
       
        topic  = opts |> Map.fetch!(:topic) #""
        msg    = opts |> Map.fetch!(:message) #""
        dup    = opts |> Map.fetch!(:dup) #bool
        qos    = opts |> Map.fetch!(:qos) #int
        retain = opts |> Map.fetch!(:retain) #bool
        funn   = opts |> Map.fetch!(:cb)

        message =
          case qos do
            0 ->
              Message.publish(topic, msg, dup, qos, retain)
            _ ->
              id = IdProvider.get_id(funn)
              Message.publish(id, topic, msg, dup, qos, retain)
          end
        :gen_tcp.send(socket,Packet.encode(message))
        {:noreply, state,timeout}

      end

      def handle_cast({:subscribe,topics,qoses, funn}, %{socket: socket, timeout: timeout} = state) do   
        id     = IdProvider.get_id(funn)
        message = Message.subscribe(id, topics, qoses)
    	  :gen_tcp.send(socket,Packet.encode(message))
        {:noreply, state ,timeout}
      end

      #get id from agent.
      def handle_cast({:unsubscribe, topics, funn}, %{socket: socket,timeout: timeout} = state) do
        id      = IdProvider.get_id(funn)
        message = Message.unsubscribe(id, topics)
        :gen_tcp.send(socket,Packet.encode(message))
        {:noreply, state,timeout}
      end

      def handle_cast(:ping, %{socket: socket, timeout: timeout} = state) do
        message = Message.ping_request
        :gen_tcp.send(socket,Packet.encode(message))
        {:noreply,state,timeout}
      end

      def handle_cast(:disconnect, %{socket: socket, timeout: timeout} = state) do
        message = Message.disconnect
        :gen_tcp.send(socket,Packet.encode(message))
        {:noreply, %{state | disconnected: true},timeout}
      end

     #RECEIVER
  	 def handle_info({:tcp, socket, msg}, %{socket: socket,timeout: timeout} = state) do
      :inet.setopts(socket, active: :once)
      %{message: message,remainder: remainder} = Packet.decode msg
  	 	case message do
         %Bus.Message.ConnAck{}  -> 
            Application.get_env(:bus, :callback).on_connect("Connected.")
         %Bus.Message.Publish{id: id,topic: topic,message: msg,qos: qos} -> 
            case qos do
               1 -> 
                  pub_ack = Message.publish_ack(id)
                  :gen_tcp.send(socket,Packet.encode(pub_ack))
               2 ->
                  pub_rec = Message.publish_receive(id)
                  :gen_tcp.send(socket,Packet.encode(pub_rec))
               _ -> :ok
            end
            Application.get_env(:bus, :callback).on_message_received(topic,msg)
         %Bus.Message.PubAck{id: id} -> #this will only call when QoS = 1, we need to free the id.
            cb = IdProvider.free_id(id)
            cb.(id)
         %Bus.Message.PubRec{id: id} -> #this will only call when QoS = 2
            pub_rel_msg = Message.publish_release(id)
            :gen_tcp.send(socket,Packet.encode(pub_rel_msg))
          %Bus.Message.PubRel{id: id} ->
            pub_comp_msg = Message.publish_complete(id)
            :gen_tcp.send(socket,Packet.encode(pub_comp_msg))
         %Bus.Message.PubComp{id: id} -> #this will only call when QoS = 2
            cb = IdProvider.free_id(id)
            cb.(id)
         %Bus.Message.SubAck{id: id} ->
            cb = IdProvider.free_id(id)
            cb.(id)
         %Bus.Message.PingResp{} -> #this is internal use.increase the timeout.
            Application.get_env(:bus, :callback).on_info("Connection Refreshed.")
         %Bus.Message.UnsubAck{id: id} ->
            cb = IdProvider.free_id(id)
            cb.(id)
         _ ->
           Application.get_env(:bus, :callback).on_error("Random packet arrived.")
            Logger.debug "Error while receiving packet."
      end
  	 	{:noreply, state,timeout}
  	 end

     def handle_info(:timeout,%{socket: socket,timeout: timeout} = state) do
         message = Message.ping_request
         :gen_tcp.send(socket,Packet.encode(message))
         {:noreply,state,timeout}
     end

  	 #This will call when tcp will be closed, try to reconnect.
  	 def handle_info({:tcp_closed, socket}, %{socket: socket,timeout: timeout,auto_reconnect: auto_reconnect, disconnected: disconnected} = state) do
      IO.inspect "Connection closed."
      Application.get_env(:bus, :callback).on_disconnect("disconnected.")
      if auto_reconnect == true and disconnected == false do
          reconnect(state)
       end
  	 end

     #if client id is int , it will convert to string.
     defp get_client_id(id) do
      case is_number(id) do
            true -> to_string(id) 
            _    -> id
      end 
     end

     defp reconnect(state) do
         IO.inspect "Reconnection in process."
        case connect(:auto) do
               {:ok,socket,timeout,auto_reconnect} ->
                   {:noreply,%{state | socket: socket,timeout: timeout, auto_reconnect: auto_reconnect, disconnected: false}}
                _ ->
                   :timer.sleep(2000)
                   reconnect(state)
          end
     end
     defp get_timeout(keep_alive) do
            if keep_alive == 0 do
                :infinity
            else
                (keep_alive*1000) - 5; # we will send pingreq before 5 sec of timeout.
            end
     end

     def terminate(reason,state) do
      :ok
     end

     def code_change(_old_ver,state,_extra) do
      {:ok, state}
     end
end