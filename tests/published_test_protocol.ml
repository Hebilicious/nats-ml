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

let () =
  test_encode_connect_defaults ();
  test_encode_connect_custom ();
  test_parse_info ();
  test_parse_msg_meta ();
  test_encode_hpub ()
