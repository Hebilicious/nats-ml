open Core
open Async

let url () =
  match Sys.getenv "NATS_URL" with
  | Some value -> Uri.of_string value
  | None -> Uri.of_string "nats://127.0.0.1:4222"

let responder client =
  Deferred.bind (Nats_client_async.subscribe client ~subject:"examples.echo" ())
    ~f:(function
      | Error error -> Deferred.return (Error error)
      | Ok subscription ->
          let rec loop () =
            Deferred.bind (Pipe.read subscription.messages) ~f:(function
              | `Eof -> Deferred.unit
              | `Ok message ->
                  Deferred.bind
                    (match message.reply_to with
                    | None -> Deferred.unit
                    | Some reply_to ->
                        Nats_client_async.publish client ~subject:reply_to "pong";
                        Deferred.unit)
                    ~f:(fun () -> loop ()))
      in
      don't_wait_for (loop ());
          Deferred.return (Ok ()))

let main () =
  Deferred.bind (Nats_client_async.connect (Some (url ()))) ~f:(fun client ->
      Deferred.bind (responder client) ~f:(function
        | Error error ->
            printf "Responder failed: %s\n" (Error.to_string_hum error);
            Nats_client_async.close client
        | Ok () ->
            Deferred.bind
              (Nats_client_async.request client ~subject:"examples.echo" "ping")
              ~f:(function
                | Ok response ->
                    printf "Request/reply response: %s\n" response;
                    Nats_client_async.close client
                | Error error ->
                    printf "Request/reply failed: %s\n"
                      (Error.to_string_hum error);
                    Nats_client_async.close client)))

let () = Thread_safe.block_on_async_exn main
