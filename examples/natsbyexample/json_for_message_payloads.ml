open Core
open Async

let url () =
  match Sys.getenv "NATS_URL" with
  | Some value -> Uri.of_string value
  | None -> Uri.of_string "nats://127.0.0.1:4222"

let main () =
  Nats_client_async.connect (Some (url ()))
  >>= fun client ->
  Monitor.protect
    ~finally:(fun () -> Nats_client_async.close client)
    (fun () ->
      let headers =
        Nats_client.Headers.empty
        |> Nats_client.Headers.add ~name:"Content-Type" ~value:"application/json"
      in
      Nats_client_async.publish_json client ~subject:"examples.json"
        ~headers
        (`Assoc [ ("message", `String "hello"); ("count", `Int 1) ]);
      printf "Published JSON payload to examples.json\n";
      Deferred.unit)

let () = Thread_safe.block_on_async_exn main
