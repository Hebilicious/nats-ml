open Core
open Async

let url () =
  match Sys.getenv "NATS_URL" with
  | Some value -> Uri.of_string value
  | None -> Uri.of_string "nats://127.0.0.1:4222"

let main () =
  Deferred.bind (Nats_client_async.connect (Some (url ()))) ~f:(fun client ->
      let headers =
        Nats_client.Headers.empty
        |> Nats_client.Headers.add ~name:"Nats-Msg-Id" ~value:"publish-json-1"
      in
      Nats_client_async.publish_json client ~subject:"examples.json"
        ~headers (`Assoc [ ("message", `String "hello") ]);
      printf "Published JSON to examples.json\n";
      Nats_client_async.close client)

let () = Thread_safe.block_on_async_exn main
