## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `bus` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:bus, "~> 0.1.0"}]
    end
    ```

  2. Ensure `bus` is started before your application:

    ```elixir
    def application do
      [applications: [:bus]]
    end
    ```
  3. Add Configuration Details in `config.ex` file.
    
    ```elixir
    config :bus, 
     		host: 'localhost',
     		port: 1883,
     		client_id: "1", #needs to be string.
     		keep_alive: 100,
     		username: "",
     		password: "",
     		auto_reconnect: true, #if client get disconnected, it will auto reconnect.
     		auto_connect: true, #this will make sure when you start :bus process, it gets connected autometically
     		callback: Bus.Callback #callback module, you need to implement callback inside.
    ```

 4. Publish 
 
     ```elixir
        Bus.Mqtt.publish(topic,message,qos)
    ```
 5. Subscribe
  
     ```elixir
        topics = ["a","b","c"] #list of topics
        qoses = [1,0,2] #list of qos in same order as topics.
        Bus.Mqtt.subscribe(topics,qoses)
    ```
  
=======
Pure Mqtt client written in Elixir

## Note
    Hello all , i will be putting documentation as soon as possible,so you guys can start using it. 
    if you reading this than you are likely to interested in Bus. 
    let me know what things you want in Bus and get any issue please point it out. 
