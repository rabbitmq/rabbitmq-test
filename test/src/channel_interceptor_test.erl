-module(channel_interceptor_test).

-include_lib("amqp_client/include/amqp_client.hrl").

-compile(export_all).

register_interceptor_test() ->
    {ok, C} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch1} = amqp_connection:open_channel(C),

    amqp_channel:call(Ch1, #'queue.declare'{queue = <<"foo">>}),

    [ChannelProc] = rabbit_channel:list(),

    [{interceptors, []}] = rabbit_channel:info(ChannelProc, [interceptors]),
    
    check_send_receive(Ch1, <<"bar">>, <<"bar">>),
    
    ok = rabbit_registry:register(channel_interceptor, 
                                  <<"stub interceptor">>, 
                                  stub_interceptor),
    [{interceptors, [{stub_interceptor, undefined}]}] = rabbit_channel:info(ChannelProc, [interceptors]),

    check_send_receive(Ch1, <<"bar">>, <<"">>),

    ok = rabbit_registry:unregister(channel_interceptor, 
                                  <<"stub interceptor">>),
    [{interceptors, []}] = rabbit_channel:info(ChannelProc, [interceptors]),
    
    check_send_receive(Ch1, <<"bar">>, <<"bar">>),
    passed.


check_send_receive(Ch1,  Send, Receive) ->
    amqp_channel:call(Ch1, 
                        #'basic.publish'{routing_key = <<"foo">>}, 
                        #amqp_msg{payload = Send}),

    {#'basic.get_ok'{}, #amqp_msg{payload = Receive}} = 
        amqp_channel:call(Ch1, #'basic.get'{queue = <<"foo">>, 
                                              no_ack = true}).
