let test_encode_connect_defaults () =
  Alcotest.(check string)
    "required CONNECT handshake"
    "CONNECT {\"verbose\":false,\"pedantic\":false}\r\n"
    (Nats_client.Protocol.encode_connect ())

let test_encode_connect_custom () =
  let connect =
    {
      Nats_client.Protocol.default_connect with
      auth_token = Some "secret";
      name = Some "nats-ml";
      protocol = 1;
      echo = true;
      headers = true;
      no_responders = true;
    }
  in
  Alcotest.(check string)
    "configurable CONNECT handshake"
    "CONNECT {\"verbose\":false,\"pedantic\":false,\"auth_token\":\"secret\",\"name\":\"nats-ml\",\"protocol\":1,\"echo\":true,\"no_responders\":true,\"headers\":true}\r\n"
    (Nats_client.Protocol.encode_connect ~connect ())

let test_parse_info () =
  match
    Nats_client.Protocol.parse_server_line
      {|INFO {"server_id":"srv","version":"2.10.0","host":"127.0.0.1","port":4222,"headers":true,"max_payload":1048576,"proto":1,"jetstream":true}|}
  with
  | Info info ->
      Alcotest.(check string) "server id" "srv" info.server_id;
      Alcotest.(check bool) "headers" true info.headers;
      Alcotest.(check bool) "jetstream" true info.jetstream
  | _ -> Alcotest.fail "expected INFO"

let test_parse_info_extended_fields () =
  match
    Nats_client.Protocol.parse_server_line
      {|INFO {"server_id":"srv","server_name":"n1","version":"2.10.0","go":"go1.22","host":"127.0.0.1","port":4222,"headers":true,"max_payload":1048576,"proto":1,"client_id":7,"auth_required":true,"tls_required":false,"tls_verify":false,"tls_available":true,"connect_urls":["a:4222","b:4222"],"ws_connect_urls":["ws:443"],"ldm":true,"git_commit":"abc123","jetstream":true,"ip":"10.0.0.1","client_ip":"10.0.0.2","nonce":"xyz","cluster":"c1","domain":"d1"}|}
  with
  | Info info ->
      Alcotest.(check (option string)) "server name" (Some "n1") info.server_name;
      Alcotest.(check (option int)) "client id" (Some 7) info.client_id;
      Alcotest.(check bool) "auth required" true info.auth_required;
      Alcotest.(check (list string))
        "connect urls"
        [ "a:4222"; "b:4222" ]
        info.connect_urls;
      Alcotest.(check (option string)) "domain" (Some "d1") info.domain
  | _ -> Alcotest.fail "expected INFO"

let test_parse_msg_meta () =
  match Nats_client.Protocol.parse_server_line "MSG greet.hello sub-1 _INBOX.42 5" with
  | Msg_meta meta ->
      Alcotest.(check string) "subject" "greet.hello" meta.subject;
      Alcotest.(check string) "sid" "sub-1" meta.sid;
      Alcotest.(check (option string)) "reply" (Some "_INBOX.42") meta.reply_to;
      Alcotest.(check int) "payload bytes" 5 meta.payload_size
  | _ -> Alcotest.fail "expected MSG"

let test_parse_err () =
  match
    Nats_client.Protocol.parse_server_line "-ERR 'Unknown Protocol Operation'"
  with
  | Err message ->
      Alcotest.(check string) "error message" "Unknown Protocol Operation" message
  | _ -> Alcotest.fail "expected ERR"

let test_parse_hmsg_meta () =
  match
    Nats_client.Protocol.parse_server_line
      "HMSG greet.hello sub-1 _INBOX.42 35 40"
  with
  | Hmsg_meta meta ->
      Alcotest.(check string) "subject" "greet.hello" meta.subject;
      Alcotest.(check string) "sid" "sub-1" meta.sid;
      Alcotest.(check (option string)) "reply" (Some "_INBOX.42") meta.reply_to;
      Alcotest.(check int) "header bytes" 35 meta.header_size;
      Alcotest.(check int) "total bytes" 40 meta.total_size
  | _ -> Alcotest.fail "expected HMSG"

let test_encode_hpub () =
  let headers =
    Nats_client.Headers.empty
    |> Nats_client.Headers.add ~name:"Nats-Msg-Id" ~value:"dedupe-1"
    |> Nats_client.Headers.add ~name:"Trace" ~value:"a"
    |> Nats_client.Headers.add ~name:"Trace" ~value:"b"
  in
  let expected_headers =
    "NATS/1.0\r\nNats-Msg-Id: dedupe-1\r\nTrace: a\r\nTrace: b\r\n\r\n"
  in
  let expected =
    Printf.sprintf "HPUB events.created %d %d\r\n%s%s\r\n"
      (String.length expected_headers)
      (String.length expected_headers + String.length "hello")
      expected_headers "hello"
  in
  Alcotest.(check string)
    "hpub frame"
    expected
    (Nats_client.Protocol.encode_hpub ~subject:"events.created" ~headers "hello")

let () =
  Alcotest.run "nats-client"
    [
      ( "protocol",
        [
          Alcotest.test_case "connect defaults" `Quick test_encode_connect_defaults;
          Alcotest.test_case "connect custom" `Quick test_encode_connect_custom;
          Alcotest.test_case "parse info" `Quick test_parse_info;
          Alcotest.test_case "parse info extended fields" `Quick
            test_parse_info_extended_fields;
          Alcotest.test_case "parse msg meta" `Quick test_parse_msg_meta;
          Alcotest.test_case "parse err" `Quick test_parse_err;
          Alcotest.test_case "parse hmsg meta" `Quick test_parse_hmsg_meta;
          Alcotest.test_case "encode hpub" `Quick test_encode_hpub;
        ] );
    ]
