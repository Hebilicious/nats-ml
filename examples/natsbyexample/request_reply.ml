open Core
open Async

(* Run a local server first:
   docker run --rm --name nats-server -p 4222:4222 nats:latest
*)

let url () =
  match Sys.getenv "NATS_URL" with
  | Some value -> Uri.of_string value
  | None -> Uri.of_string "nats://127.0.0.1:4222"

let start_responder client =
  Nats_client_async.subscribe client ~subject:"examples.echo" ()
  >>= function
  | Error error -> Deferred.return (Error error)
  | Ok subscription ->
      let rec loop () =
        Pipe.read subscription.messages
        >>= function
        | `Eof -> Deferred.unit
        | `Ok message ->
            (match message.reply_to with
            | None -> ()
            | Some reply_to ->
                Nats_client_async.publish client ~subject:reply_to message.payload);
            loop ()
      in
      don't_wait_for (loop ());
      Deferred.Or_error.return ()

let main () =
  Nats_client_async.connect (Some (url ()))
  >>= fun client ->
  Monitor.protect
    ~finally:(fun () -> Nats_client_async.close client)
    (fun () ->
      start_responder client
      >>= function
      | Error error -> Error.raise error
      | Ok () ->
          Nats_client_async.request client ~subject:"examples.echo" "ping"
          >>= function
          | Ok response ->
              printf "Request/reply response: %s\n" response;
              Deferred.unit
          | Error error -> Error.raise error)

let () = Thread_safe.block_on_async_exn main
