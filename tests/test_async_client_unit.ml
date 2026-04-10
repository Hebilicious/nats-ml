open Core
open Async

let run_async f = Thread_safe.block_on_async_exn f

let test_disabled_publish_is_noop () =
  let client = run_async (fun () -> Nats_client_async.connect None) in
  Nats_client_async.publish client ~subject:"events.created" "hello";
  Nats_client_async.publish_json client ~subject:"events.created"
    (`Assoc [ ("hello", `String "world") ]);
  Alcotest.(check (of_pp Nats_client_async.pp_publish_result))
    "publish_result"
    `Dropped
    (Nats_client_async.publish_result client ~subject:"events.created" "hello")

let test_disabled_live_operations_fail () =
  let client = run_async (fun () -> Nats_client_async.connect None) in
  let sub =
    run_async (fun () -> Nats_client_async.subscribe client ~subject:"events.*" ())
  in
  let req =
    run_async (fun () -> Nats_client_async.request client ~subject:"events.created" "hello")
  in
  let unsub =
    run_async (fun () -> Nats_client_async.unsubscribe client (Nats_client.Sid.create 8))
  in
  Alcotest.(check bool) "subscribe error" true (Result.is_error sub);
  Alcotest.(check bool) "request error" true (Result.is_error req);
  Alcotest.(check bool) "unsubscribe error" true (Result.is_error unsub)

let () =
  Alcotest.run "nats-client-async"
    [
      ( "disabled",
        [
          Alcotest.test_case "publish is noop" `Quick test_disabled_publish_is_noop;
          Alcotest.test_case "live operations fail" `Quick
            test_disabled_live_operations_fail;
        ] );
    ]
