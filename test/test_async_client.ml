open Core
open Async

let run_async f = Thread_safe.block_on_async_exn f
let info_line =
  {|INFO {"server_id":"srv","version":"2.10.0","host":"127.0.0.1","port":4222,"headers":true,"max_payload":1048576,"proto":1,"jetstream":true}|}

let with_fake_server handler =
  Tcp.Server.create
    ~on_handler_error:`Raise
    Tcp.Where_to_listen.of_port_chosen_by_os
    handler
  >>= fun server ->
  Deferred.return (server, Tcp.Server.listening_on server)

let last_field line =
  String.split line ~on:' ' |> List.last_exn

let read_exact_string reader length =
  let buffer = Bytes.create length in
  Reader.really_read reader buffer
  >>= function
  | `Ok ->
      Deferred.return
        (Bytes.unsafe_to_string ~no_mutation_while_string_reachable:buffer)
  | `Eof _ -> Deferred.return "<eof>"

let await_or_fail label deferred =
  Clock_ns.with_timeout (Time_ns.Span.of_sec 1.) deferred
  >>= function
  | `Result value -> Deferred.return value
  | `Timeout -> failwithf "%s timed out" label ()

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

let test_connect_sends_required_handshake () =
  let observed = Ivar.create () in
  let client =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Ok line ->
                Ivar.fill_if_empty observed line;
                Deferred.unit
            | `Eof ->
                Ivar.fill_if_empty observed "<eof>";
                Deferred.unit)
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            Nats_client_async.connect
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))))
  in
  Alcotest.(check string)
    "connect line"
    "CONNECT {\"verbose\":false,\"pedantic\":false}"
    (run_async (fun () -> Ivar.read observed));
  run_async (fun () -> Nats_client_async.close client)

let test_connect_sends_configured_handshake () =
  let observed = Ivar.create () in
  let client =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Ok line ->
                Ivar.fill_if_empty observed line;
                Deferred.unit
            | `Eof ->
                Ivar.fill_if_empty observed "<eof>";
                Deferred.unit)
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            let connect =
              {
                Nats_client.Protocol.default_connect with
                name = Some "nats-ml";
                protocol = 1;
                echo = true;
                headers = true;
              }
            in
            Nats_client_async.connect ~connect
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))))
  in
  Alcotest.(check string)
    "connect line"
    {|CONNECT {"verbose":false,"pedantic":false,"name":"nats-ml","protocol":1,"echo":true,"headers":true}|}
    (run_async (fun () -> Ivar.read observed));
  run_async (fun () -> Nats_client_async.close client)

let test_publish_sends_pub_frame () =
  let observed = Ivar.create () in
  let client =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Eof -> Deferred.unit
            | `Ok _ ->
                Reader.read_line reader
                >>= fun pub ->
                Reader.read_line reader
                >>= fun payload ->
                (match pub, payload with
                | `Ok pub, `Ok payload ->
                    Ivar.fill_if_empty observed (pub, payload);
                    Deferred.unit
                | _ ->
                    Ivar.fill_if_empty observed ("<eof>", "<eof>");
                    Deferred.unit))
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            Nats_client_async.connect
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))))
  in
  Nats_client_async.publish client ~subject:"events.created" "hello";
  let pub, payload = run_async (fun () -> Ivar.read observed) in
  Alcotest.(check string) "pub line" "PUB events.created 5" pub;
  Alcotest.(check string) "payload" "hello" payload;
  run_async (fun () -> Nats_client_async.close client)

let test_publish_json_sends_json_payload () =
  let observed = Ivar.create () in
  let client =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Eof -> Deferred.unit
            | `Ok _ ->
                Reader.read_line reader
                >>= fun _pub ->
                Reader.read_line reader
                >>= function
                | `Ok payload ->
                    Ivar.fill_if_empty observed payload;
                    Deferred.unit
                | `Eof ->
                    Ivar.fill_if_empty observed "<eof>";
                    Deferred.unit)
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            Nats_client_async.connect
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))))
  in
  Nats_client_async.publish_json client ~subject:"events.created"
    (`Assoc [ ("hello", `String "world") ]);
  Alcotest.(check string)
    "json payload"
    "{\"hello\":\"world\"}"
    (run_async (fun () -> Ivar.read observed));
  run_async (fun () -> Nats_client_async.close client)

let test_publish_with_headers_sends_hpub () =
  let observed = Ivar.create () in
  let client =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Eof -> Deferred.unit
            | `Ok _ ->
                Reader.read_line reader
                >>= fun hpub ->
                (match hpub with
                | `Ok line ->
                    let total_bytes =
                      String.split line ~on:' '
                      |> List.last_exn
                      |> Int.of_string
                    in
                    read_exact_string reader total_bytes
                    >>= fun header_and_payload ->
                    read_exact_string reader 2
                    >>= fun _crlf ->
                    Ivar.fill_if_empty observed (hpub, header_and_payload);
                    Deferred.unit
                | `Eof ->
                    Ivar.fill_if_empty observed (`Eof, "<eof>");
                    Deferred.unit))
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            Nats_client_async.connect
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))))
  in
  let headers =
    Nats_client.Headers.empty
    |> Nats_client.Headers.add ~name:"Nats-Msg-Id" ~value:"dedupe-1"
  in
  Nats_client_async.publish client ~subject:"events.created" ~headers "hello";
  let line, body = run_async (fun () -> Ivar.read observed) in
  let line =
    match line with
    | `Ok line -> line
    | `Eof -> "<eof>"
  in
  Alcotest.(check bool) "uses HPUB" true (String.is_prefix line ~prefix:"HPUB events.created ");
  Alcotest.(check bool) "contains header" true
    (String.is_substring body ~substring:"Nats-Msg-Id: dedupe-1");
  Alcotest.(check bool) "contains payload" true
    (String.is_suffix body ~suffix:"hello");
  run_async (fun () -> Nats_client_async.close client)

let test_server_ping_gets_pong () =
  let observed = Ivar.create () in
  let client =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Eof -> Deferred.unit
            | `Ok _ ->
                Writer.write writer "PING\r\n";
                Writer.flushed writer
                >>= fun () ->
                Reader.read_line reader
                >>= function
                | `Ok line ->
                    Ivar.fill_if_empty observed line;
                    Deferred.unit
                | `Eof ->
                    Ivar.fill_if_empty observed "<eof>";
                    Deferred.unit)
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            Nats_client_async.connect
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))))
  in
  Alcotest.(check string) "pong" "PONG" (run_async (fun () -> Ivar.read observed));
  run_async (fun () -> Nats_client_async.close client)

let test_client_sends_periodic_ping () =
  let observed = Ivar.create () in
  let client =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Eof -> Deferred.unit
            | `Ok _ ->
                Reader.read_line reader
                >>= function
                | `Ok line ->
                    Ivar.fill_if_empty observed line;
                    Deferred.unit
                | `Eof ->
                    Ivar.fill_if_empty observed "<eof>";
                    Deferred.unit)
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            Nats_client_async.connect
              ~ping_interval:(Time_ns.Span.of_ms 10.)
              ~ping_timeout:(Time_ns.Span.of_ms 100.)
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))))
  in
  Alcotest.(check string) "ping" "PING" (run_async (fun () -> Ivar.read observed));
  run_async (fun () -> Nats_client_async.close client)

let test_subscribe_receives_messages () =
  let client, subscription =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Eof -> Deferred.unit
            | `Ok _ ->
                Reader.read_line reader
                >>= function
                | `Ok line ->
                    let sid = last_field line in
                    Writer.write writer
                      (Printf.sprintf "MSG events.created %s 5\r\nhello\r\n" sid);
                    Writer.flushed writer
                | `Eof -> Deferred.unit)
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            Nats_client_async.connect
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))
            >>= fun client ->
            Nats_client_async.subscribe client ~subject:"events.*" ()
            >>= function
            | Error error -> Error.raise error
            | Ok subscription -> Deferred.return (client, subscription)))
  in
  let message =
    run_async (fun () ->
        Pipe.read subscription.Nats_client_async.messages
        >>= function
        | `Ok message -> Deferred.return message
        | `Eof -> failwith "expected message")
  in
  Alcotest.(check string) "subject" "events.created" message.subject;
  Alcotest.(check string) "payload" "hello" message.payload;
  run_async (fun () -> Nats_client_async.close client)

let test_subscribe_receives_hmsg_with_headers () =
  let client, subscription =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            let header_block =
              "NATS/1.0\r\nNats-Msg-Id: dedupe-1\r\nTrace: a\r\n\r\n"
            in
            let payload = "hello" in
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Eof -> Deferred.unit
            | `Ok _ ->
                Reader.read_line reader
                >>= function
                | `Ok line ->
                    let sid = last_field line in
                    Writer.write writer
                      (Printf.sprintf "HMSG events.created %s %d %d\r\n%s%s\r\n"
                         sid
                         (String.length header_block)
                         (String.length header_block + String.length payload)
                         header_block payload);
                    Writer.flushed writer
                | `Eof -> Deferred.unit)
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            let connect =
              { Nats_client.Protocol.default_connect with headers = true }
            in
            Nats_client_async.connect ~connect
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))
            >>= fun client ->
            Nats_client_async.subscribe client ~subject:"events.*" ()
            >>= function
            | Error error -> Error.raise error
            | Ok subscription -> Deferred.return (client, subscription)))
  in
  let message =
    run_async (fun () ->
        Pipe.read subscription.Nats_client_async.messages
        >>= function
        | `Ok message -> Deferred.return message
        | `Eof -> failwith "expected HMSG")
  in
  Alcotest.(check string) "subject" "events.created" message.subject;
  Alcotest.(check string) "payload" "hello" message.payload;
  Alcotest.(check (option (list (pair string string))))
    "headers"
    (Some [ ("Nats-Msg-Id", "dedupe-1"); ("Trace", "a") ])
    (Option.map message.headers ~f:Nats_client.Headers.to_list);
  run_async (fun () -> Nats_client_async.close client)

let test_request_reply_round_trip () =
  let client =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Eof -> Deferred.unit
            | `Ok _ ->
                Reader.read_line reader
                >>= fun sub ->
                Reader.read_line reader
                >>= fun pub ->
                Reader.read_line reader
                >>= fun _payload ->
                (match sub, pub with
                | `Ok sub, `Ok pub ->
                    let sid = last_field sub in
                    let parts = String.split pub ~on:' ' in
                    let reply_to = List.nth_exn parts 2 in
                    Writer.write writer
                      (Printf.sprintf "MSG %s %s 5\r\nworld\r\n" reply_to sid);
                    Writer.flushed writer
                | _ -> Deferred.unit))
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            Nats_client_async.connect
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))))
  in
  let response =
    run_async (fun () ->
        Nats_client_async.request client ~subject:"events.created" "hello"
        >>= function
        | Ok response -> Deferred.return response
        | Error error -> Error.raise error)
  in
  Alcotest.(check string) "response" "world" response;
  run_async (fun () -> Nats_client_async.close client)

let test_publish_drops_after_disconnect () =
  let client =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Ok _ -> Writer.close writer
            | `Eof -> Deferred.unit)
        >>= fun (server, port) ->
        Monitor.protect
          ~finally:(fun () -> Tcp.Server.close server)
          (fun () ->
            Nats_client_async.connect
              ~reconnect_initial:(Time_ns.Span.of_ms 10.)
              ~reconnect_max:(Time_ns.Span.of_ms 20.)
              (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port)))))
  in
  run_async (fun () -> Clock_ns.after (Time_ns.Span.of_ms 50.));
  Alcotest.(check (of_pp Nats_client_async.pp_publish_result))
    "drops while disconnected"
    `Dropped
    (Nats_client_async.publish_result client ~subject:"events.created" "hello");
  run_async (fun () -> Nats_client_async.close client)

let test_reconnect_replays_subscriptions () =
  let replayed_sub = Ivar.create () in
  let attempts = ref 0 in
  let server, port =
    run_async (fun () ->
        with_fake_server (fun _address reader writer ->
            incr attempts;
            let attempt = !attempts in
            Writer.write writer (info_line ^ "\r\n");
            Writer.flushed writer
            >>= fun () ->
            Reader.read_line reader
            >>= function
            | `Eof -> Deferred.unit
            | `Ok _ -> (
                match attempt with
                | 1 ->
                    Reader.read_line reader
                    >>= (function
                          | `Ok _ -> Writer.close writer >>= fun () -> Reader.close reader
                          | `Eof -> Deferred.unit)
                | 2 ->
                    Reader.read_line reader
                    >>= (function
                          | `Ok line ->
                              Ivar.fill_if_empty replayed_sub line;
                              let sid = last_field line in
                              Writer.write writer
                                (Printf.sprintf "MSG events.created %s 5\r\nhello\r\n" sid);
                              Writer.flushed writer
                          | `Eof -> Deferred.unit)
                | _ -> Deferred.unit))
        )
  in
  let client =
    run_async (fun () ->
        Nats_client_async.connect
          ~reconnect_initial:(Time_ns.Span.of_ms 10.)
          ~reconnect_max:(Time_ns.Span.of_ms 20.)
          (Some (Uri.of_string (Printf.sprintf "nats://127.0.0.1:%d" port))))
  in
  let subscription =
    run_async (fun () ->
        Nats_client_async.subscribe client ~subject:"events.*" ()
        >>= function
        | Error error -> Error.raise error
        | Ok subscription -> Deferred.return subscription)
  in
  let replayed_sub =
    run_async (fun () -> await_or_fail "replayed SUB" (Ivar.read replayed_sub))
  in
  Alcotest.(check bool) "replayed subject" true
    (String.is_prefix replayed_sub ~prefix:"SUB events.* ");
  let message =
    run_async (fun () ->
        await_or_fail "replayed message"
          (Pipe.read subscription.Nats_client_async.messages
          >>= function
          | `Ok message -> Deferred.return message
          | `Eof -> failwith "expected replayed message"))
  in
  Alcotest.(check string) "replayed payload" "hello" message.payload;
  run_async (fun () -> Nats_client_async.close client >>= fun () -> Tcp.Server.close server)

let () =
  Alcotest.run "nats-client-async"
    [
      ( "disabled",
        [
          Alcotest.test_case "publish is noop" `Quick test_disabled_publish_is_noop;
          Alcotest.test_case "live operations fail" `Quick
            test_disabled_live_operations_fail;
        ] );
      ( "connect",
        [
          Alcotest.test_case "handshake" `Quick test_connect_sends_required_handshake;
          Alcotest.test_case "handshake custom connect" `Quick
            test_connect_sends_configured_handshake;
          Alcotest.test_case "publish" `Quick test_publish_sends_pub_frame;
          Alcotest.test_case "publish json" `Quick test_publish_json_sends_json_payload;
          Alcotest.test_case "publish headers" `Quick test_publish_with_headers_sends_hpub;
          Alcotest.test_case "server ping" `Quick test_server_ping_gets_pong;
          Alcotest.test_case "client ping" `Quick test_client_sends_periodic_ping;
          Alcotest.test_case "subscribe" `Quick test_subscribe_receives_messages;
          Alcotest.test_case "subscribe hmsg" `Quick
            test_subscribe_receives_hmsg_with_headers;
          Alcotest.test_case "request" `Quick test_request_reply_round_trip;
          Alcotest.test_case "drop after disconnect" `Quick test_publish_drops_after_disconnect;
          Alcotest.test_case "reconnect replays subscriptions" `Quick
            test_reconnect_replays_subscriptions;
        ] );
    ]
