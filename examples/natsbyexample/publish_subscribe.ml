open Core
open Async

let url () =
  match Sys.getenv "NATS_URL" with
  | Some value -> Uri.of_string value
  | None -> Uri.of_string "nats://127.0.0.1:4222"

let rec read_n messages acc =
  if acc = 0
  then Deferred.unit
  else
    Pipe.read messages
    >>= function
    | `Eof -> Deferred.unit
    | `Ok message ->
        printf "'%s' received on %s\n" message.Nats_client.Protocol.payload
          message.subject;
        read_n messages (acc - 1)

let main () =
  Nats_client_async.connect (Some (url ()))
  >>= fun client ->
  Monitor.protect
    ~finally:(fun () -> Nats_client_async.close client)
    (fun () ->
      Nats_client_async.subscribe client ~subject:"greet.*" ()
      >>= function
      | Error error -> Error.raise error
      | Ok subscription ->
          List.iter [ "greet.sue"; "greet.bob"; "greet.pam" ] ~f:(fun subject ->
              Nats_client_async.publish client ~subject "hello");
          read_n subscription.messages 3)

let () = Thread_safe.block_on_async_exn main
