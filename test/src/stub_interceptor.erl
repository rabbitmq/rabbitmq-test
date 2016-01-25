-module(stub_interceptor).

-behaviour(rabbit_channel_interceptor).

-include_lib("rabbit_common/include/rabbit.hrl").
-include_lib("rabbit_common/include/rabbit_framing.hrl").


-compile(export_all).

init(_Ch) ->
    undefined.

description() ->
    [{description,
      <<"Empties payload on publish">>}].

intercept(#'basic.publish'{} = Method, Content, _IState) ->
    DecodedContent = rabbit_binary_parser:ensure_content_decoded(Content),
    Content2 = Content#content{payload_fragments_rev = []},
    {Method, Content2};

intercept(Method, Content, _VHost) ->
    {Method, Content}.

applies_to() ->
    ['basic.publish'].
