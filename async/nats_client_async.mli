open Core
open Async

type publish_result = [ `Queued | `Dropped ]

type subscription = {
  sid : Nats_client.Sid.t;
  subject : string;
  messages : Nats_client.Protocol.message Pipe.Reader.t;
}

type client

val pp_publish_result : Format.formatter -> publish_result -> unit

val connect :
  ?connect:Nats_client.Protocol.connect ->
  ?ping_interval:Time_ns.Span.t ->
  ?ping_timeout:Time_ns.Span.t ->
  ?reconnect_initial:Time_ns.Span.t ->
  ?reconnect_max:Time_ns.Span.t ->
  Uri.t option ->
  client Deferred.t

val publish :
  client ->
  subject:string ->
  ?reply_to:string ->
  ?headers:Nats_client.Headers.t ->
  string ->
  unit

val publish_result :
  client ->
  subject:string ->
  ?reply_to:string ->
  ?headers:Nats_client.Headers.t ->
  string ->
  publish_result

val publish_json :
  client ->
  subject:string ->
  ?reply_to:string ->
  ?headers:Nats_client.Headers.t ->
  Yojson.Safe.t ->
  unit

val subscribe :
  client ->
  subject:string ->
  ?queue_group:string ->
  ?sid:Nats_client.Sid.t ->
  unit ->
  subscription Or_error.t Deferred.t

val unsubscribe :
  client ->
  ?max_msgs:int ->
  Nats_client.Sid.t ->
  unit Or_error.t Deferred.t

val request :
  client ->
  subject:string ->
  ?headers:Nats_client.Headers.t ->
  ?timeout:Time_ns.Span.t ->
  string ->
  string Or_error.t Deferred.t

val close : client -> unit Deferred.t
