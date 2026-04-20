(** Async NATS client.

    This package provides a TCP client built on Jane Street Async. It uses
    [nats-client] for protocol encoding and parsing, and adds connection
    management, publish/subscribe, request/reply, keepalive, and reconnect
    handling. *)

open Core
open Async

type publish_result = [ `Queued | `Dropped ]
(** The result of attempting to enqueue a publish request. *)

type subscription = {
  sid : Nats_client.Sid.t;
  subject : string;
  messages : Nats_client.Protocol.message Pipe.Reader.t;
}
(** An active subscription and its incoming message pipe. *)

type client
(** A NATS client.

    A client may be disabled when created with [connect None]. *)

val pp_publish_result : Format.formatter -> publish_result -> unit
(** Pretty-printer for [publish_result]. *)

val connect :
  ?connect:Nats_client.Protocol.connect ->
  ?ping_interval:Time_ns.Span.t ->
  ?ping_timeout:Time_ns.Span.t ->
  ?reconnect_initial:Time_ns.Span.t ->
  ?reconnect_max:Time_ns.Span.t ->
  Uri.t option ->
  client Deferred.t
(** Connect to a NATS server.

    [Some uri] starts a TCP connection to the given [nats://] URI and resolves
    once the first connection is established. The client reconnects with
    exponential backoff after later disconnects.

    [None] returns a disabled client. Publishing to a disabled client is a
    no-op, while subscription, unsubscribe, and request calls return errors. *)

val publish :
  client ->
  subject:string ->
  ?reply_to:string ->
  ?headers:Nats_client.Headers.t ->
  string ->
  unit
(** Fire-and-forget publish.

    The payload is silently dropped when the client is disabled, closed,
    disconnected, or its pending queue is full. Use [publish_result] when the
    caller needs to observe that enqueue decision. *)

val publish_result :
  client ->
  subject:string ->
  ?reply_to:string ->
  ?headers:Nats_client.Headers.t ->
  string ->
  publish_result
(** Publish and return whether the frame was queued or dropped. *)

val publish_json :
  client ->
  subject:string ->
  ?reply_to:string ->
  ?headers:Nats_client.Headers.t ->
  Yojson.Safe.t ->
  unit
(** Publish a JSON payload encoded with [Yojson.Safe.to_string]. *)

val subscribe :
  client ->
  subject:string ->
  ?queue_group:string ->
  ?sid:Nats_client.Sid.t ->
  unit ->
  subscription Or_error.t Deferred.t
(** Subscribe to a subject.

    [queue_group] creates a queue subscription. [sid] may be supplied when a
    caller needs a stable subscription id; otherwise one is generated. *)

val unsubscribe :
  client ->
  ?max_msgs:int ->
  Nats_client.Sid.t ->
  unit Or_error.t Deferred.t
(** Unsubscribe by subscription id.

    [max_msgs] asks the server to deliver at most that many additional messages
    before removing the subscription. *)

val request :
  client ->
  subject:string ->
  ?headers:Nats_client.Headers.t ->
  ?timeout:Time_ns.Span.t ->
  string ->
  string Or_error.t Deferred.t
(** Send a request and wait for one response payload.

    A private inbox subscription is created for the response and removed before
    the deferred resolves. [timeout] bounds the wait for the response. *)

val close : client -> unit Deferred.t
(** Close the client and all subscription pipes. *)
