let fail fmt = Printf.ksprintf failwith fmt

let assert_equal ~message pp equal expected actual =
  if not (equal expected actual) then
    fail "%s: expected %s, got %s" message (pp expected) (pp actual)

let pp_string value = value
let pp_bool = string_of_bool
let pp_int = string_of_int

let pp_option pp = function
  | None -> "None"
  | Some value -> "Some(" ^ pp value ^ ")"

let pp_string_list values = "[" ^ String.concat "; " values ^ "]"

let pp_pair_list values =
  let entries =
    List.map (fun (name, value) -> "(" ^ name ^ ", " ^ value ^ ")") values
  in
  "[" ^ String.concat "; " entries ^ "]"

let test_encode_connect_defaults () =
  let actual = Nats_client.Protocol.encode_connect () in
  assert_equal
    ~message:"CONNECT defaults"
    pp_string
    String.equal
    "CONNECT {\"verbose\":false,\"pedantic\":false}\r\n"
    actual

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
  let actual = Nats_client.Protocol.encode_connect ~connect () in
  assert_equal
    ~message:"CONNECT custom"
    pp_string
    String.equal
    "CONNECT {\"verbose\":false,\"pedantic\":false,\"auth_token\":\"secret\",\"name\":\"nats-ml\",\"protocol\":1,\"echo\":true,\"no_responders\":true,\"headers\":true}\r\n"
    actual

let test_parse_info () =
  match
    Nats_client.Protocol.parse_server_line
      {|INFO {"server_id":"srv","version":"2.10.0","host":"127.0.0.1","port":4222,"headers":true,"max_payload":1048576,"proto":1,"jetstream":true}|}
  with
  | Info info ->
      assert_equal ~message:"server id" pp_string String.equal "srv" info.server_id;
      assert_equal ~message:"headers" pp_bool Bool.equal true info.headers;
      assert_equal ~message:"jetstream" pp_bool Bool.equal true info.jetstream
  | _ -> fail "expected INFO"

let test_parse_msg_meta () =
  match Nats_client.Protocol.parse_server_line "MSG greet.hello sub-1 _INBOX.42 5" with
  | Msg_meta meta ->
      assert_equal ~message:"subject" pp_string String.equal "greet.hello" meta.subject;
      assert_equal ~message:"sid" pp_string String.equal "sub-1" meta.sid;
      assert_equal
        ~message:"reply"
        (pp_option pp_string)
        (Option.equal String.equal)
        (Some "_INBOX.42")
        meta.reply_to;
      assert_equal ~message:"payload size" pp_int Int.equal 5 meta.payload_size
  | _ -> fail "expected MSG"

let test_parse_info_extended_fields () =
  match
    Nats_client.Protocol.parse_server_line
      {|INFO {"server_id":"srv","server_name":"n1","version":"2.10.0","go":"go1.22","host":"127.0.0.1","port":4222,"headers":true,"max_payload":1048576,"proto":1,"client_id":7,"auth_required":true,"tls_required":false,"tls_verify":false,"tls_available":true,"connect_urls":["a:4222","b:4222"],"ws_connect_urls":["ws:443"],"ldm":true,"git_commit":"abc123","jetstream":true,"ip":"10.0.0.1","client_ip":"10.0.0.2","nonce":"xyz","cluster":"c1","domain":"d1"}|}
  with
  | Info info ->
      assert_equal
        ~message:"server name"
        (pp_option pp_string)
        (Option.equal String.equal)
        (Some "n1")
        info.server_name;
      assert_equal
        ~message:"client id"
        (pp_option pp_int)
        (Option.equal Int.equal)
        (Some 7)
        info.client_id;
      assert_equal ~message:"auth required" pp_bool Bool.equal true info.auth_required;
      assert_equal
        ~message:"connect urls"
        pp_string_list
        ( = )
        [ "a:4222"; "b:4222" ]
        info.connect_urls;
      assert_equal
        ~message:"domain"
        (pp_option pp_string)
        (Option.equal String.equal)
        (Some "d1")
        info.domain
  | _ -> fail "expected INFO"

let test_parse_err () =
  match
    Nats_client.Protocol.parse_server_line "-ERR 'Unknown Protocol Operation'"
  with
  | Err message ->
      assert_equal
        ~message:"error message"
        pp_string
        String.equal
        "Unknown Protocol Operation"
        message
  | _ -> fail "expected ERR"

let test_parse_hmsg_meta () =
  match
    Nats_client.Protocol.parse_server_line
      "HMSG greet.hello sub-1 _INBOX.42 35 40"
  with
  | Hmsg_meta meta ->
      assert_equal ~message:"subject" pp_string String.equal "greet.hello" meta.subject;
      assert_equal ~message:"sid" pp_string String.equal "sub-1" meta.sid;
      assert_equal
        ~message:"reply"
        (pp_option pp_string)
        (Option.equal String.equal)
        (Some "_INBOX.42")
        meta.reply_to;
      assert_equal ~message:"header bytes" pp_int Int.equal 35 meta.header_size;
      assert_equal ~message:"total bytes" pp_int Int.equal 40 meta.total_size
  | _ -> fail "expected HMSG"

let test_encode_pub () =
  let actual =
    Nats_client.Protocol.encode_pub ~subject:"events.created" ~reply_to:"_INBOX.1"
      "hello"
  in
  assert_equal
    ~message:"PUB"
    pp_string
    String.equal
    "PUB events.created _INBOX.1 5\r\nhello\r\n"
    actual

let test_encode_sub () =
  let actual =
    Nats_client.Protocol.encode_sub ~subject:"events.*" ~queue_group:"workers"
      ~sid:"sub-1" ()
  in
  assert_equal
    ~message:"SUB"
    pp_string
    String.equal
    "SUB events.* workers sub-1\r\n"
    actual

let test_encode_unsub () =
  let actual = Nats_client.Protocol.encode_unsub ~sid:"sub-1" ~max_msgs:5 () in
  assert_equal
    ~message:"UNSUB"
    pp_string
    String.equal
    "UNSUB sub-1 5\r\n"
    actual

let test_ping_pong () =
  assert_equal
    ~message:"PING"
    pp_string
    String.equal
    "PING\r\n"
    (Nats_client.Protocol.encode_ping ());
  assert_equal
    ~message:"PONG"
    pp_string
    String.equal
    "PONG\r\n"
    (Nats_client.Protocol.encode_pong ())

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
  let actual =
    Nats_client.Protocol.encode_hpub ~subject:"events.created" ~headers "hello"
  in
  assert_equal ~message:"HPUB encoding" pp_string String.equal expected actual

let test_headers_roundtrip () =
  let headers =
    Nats_client.Headers.of_list [ ("Trace", "a") ]
    |> Nats_client.Headers.add ~name:"Trace" ~value:"b"
    |> Nats_client.Headers.add ~name:"Nats-Msg-Id" ~value:"dedupe-1"
  in
  assert_equal
    ~message:"headers roundtrip"
    pp_pair_list
    ( = )
    [ ("Trace", "a"); ("Trace", "b"); ("Nats-Msg-Id", "dedupe-1") ]
    (Nats_client.Headers.to_list headers)

let () =
  test_encode_connect_defaults ();
  test_encode_connect_custom ();
  test_parse_info ();
  test_parse_info_extended_fields ();
  test_parse_msg_meta ();
  test_parse_err ();
  test_parse_hmsg_meta ();
  test_encode_pub ();
  test_encode_sub ();
  test_encode_unsub ();
  test_ping_pong ();
  test_encode_hpub ();
  test_headers_roundtrip ()
