open Core
open Async

let fail fmt = Printf.ksprintf failwith fmt

let run_async f = Thread_safe.block_on_async_exn f

let test_disabled_publish_is_noop () =
  let client = run_async (fun () -> Nats_client_async.connect None) in
  Nats_client_async.publish client ~subject:"events.created" "hello";
  Nats_client_async.publish_json client ~subject:"events.created"
    (`Assoc [ ("hello", `String "world") ]);
  match Nats_client_async.publish_result client ~subject:"events.created" "hello" with
  | `Dropped -> ()
  | result ->
      fail "publish_result: expected `Dropped, got %s"
        (Format.asprintf "%a" Nats_client_async.pp_publish_result result)

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
  if not (Result.is_error sub) then fail "subscribe should fail for disabled client";
  if not (Result.is_error req) then fail "request should fail for disabled client";
  if not (Result.is_error unsub) then fail "unsubscribe should fail for disabled client"

let () =
  test_disabled_publish_is_noop ();
  test_disabled_live_operations_fail ()
