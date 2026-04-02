type connect = {
  verbose : bool;
  pedantic : bool;
  tls_required : bool;
  auth_token : string option;
  user : string option;
  pass : string option;
  name : string option;
  lang : string option;
  version : string option;
  protocol : int;
  echo : bool;
  sig_ : string option;
  jwt : string option;
  no_responders : bool;
  headers : bool;
  nkey : string option;
}

type info = {
  server_id : string;
  server_name : string option;
  version : string;
  go : string option;
  host : string;
  port : int;
  headers : bool;
  max_payload : int;
  proto : int;
  client_id : int option;
  auth_required : bool;
  tls_required : bool;
  tls_verify : bool;
  tls_available : bool;
  connect_urls : string list;
  ws_connect_urls : string list;
  ldm : bool;
  git_commit : string option;
  jetstream : bool;
  ip : string option;
  client_ip : string option;
  nonce : string option;
  cluster : string option;
  domain : string option;
}

type msg_meta = {
  subject : string;
  sid : string;
  reply_to : string option;
  payload_size : int;
}

type hmsg_meta = {
  subject : string;
  sid : string;
  reply_to : string option;
  header_size : int;
  total_size : int;
}

type message = {
  subject : string;
  sid : string;
  reply_to : string option;
  payload : string;
  headers : Headers.t option;
}

type parsed_line =
  | Ping
  | Pong
  | Ok
  | Err of string
  | Info of info
  | Msg_meta of msg_meta
  | Hmsg_meta of hmsg_meta

let default_connect =
  {
    verbose = false;
    pedantic = false;
    tls_required = false;
    auth_token = None;
    user = None;
    pass = None;
    name = None;
    lang = None;
    version = None;
    protocol = 0;
    echo = false;
    sig_ = None;
    jwt = None;
    no_responders = false;
    headers = false;
    nkey = None;
  }

let encode_connect ?(connect = default_connect) () =
  let add_some name value fields =
    match value with
    | None -> fields
    | Some value -> (name, value) :: fields
  in
  let add_bool name enabled fields =
    if enabled then (name, `Bool true) :: fields else fields
  in
  let add_int name value fields =
    if value <> 0 then (name, `Int value) :: fields else fields
  in
  let fields =
    []
    |> add_some "nkey" (Option.map (fun value -> `String value) connect.nkey)
    |> add_bool "headers" connect.headers
    |> add_bool "no_responders" connect.no_responders
    |> add_some "jwt" (Option.map (fun value -> `String value) connect.jwt)
    |> add_some "sig" (Option.map (fun value -> `String value) connect.sig_)
    |> add_bool "echo" connect.echo
    |> add_int "protocol" connect.protocol
    |> add_some "version" (Option.map (fun value -> `String value) connect.version)
    |> add_some "lang" (Option.map (fun value -> `String value) connect.lang)
    |> add_some "name" (Option.map (fun value -> `String value) connect.name)
    |> add_some "pass" (Option.map (fun value -> `String value) connect.pass)
    |> add_some "user" (Option.map (fun value -> `String value) connect.user)
    |> add_some "auth_token"
         (Option.map (fun value -> `String value) connect.auth_token)
    |> add_bool "tls_required" connect.tls_required
    |> fun fields -> ("pedantic", `Bool connect.pedantic) :: fields
    |> fun fields -> ("verbose", `Bool connect.verbose) :: fields
  in
  "CONNECT " ^ Yojson.Safe.to_string (`Assoc fields) ^ "\r\n"

let header_block headers =
  let buffer = Buffer.create 64 in
  Buffer.add_string buffer "NATS/1.0\r\n";
  List.iter
    (fun (name, value) ->
      Buffer.add_string buffer name;
      Buffer.add_string buffer ": ";
      Buffer.add_string buffer value;
      Buffer.add_string buffer "\r\n")
    (Headers.to_list headers);
  Buffer.add_string buffer "\r\n";
  Buffer.contents buffer

let encode_pub ~subject ?reply_to payload =
  Printf.sprintf "PUB %s%s %d\r\n%s\r\n" subject
    (match reply_to with None -> "" | Some reply_to -> " " ^ reply_to)
    (String.length payload) payload

let encode_sub ~subject ?queue_group ~sid () =
  Printf.sprintf "SUB %s%s %s\r\n" subject
    (match queue_group with None -> "" | Some queue_group -> " " ^ queue_group)
    sid

let encode_unsub ~sid ?max_msgs () =
  Printf.sprintf "UNSUB %s%s\r\n" sid
    (match max_msgs with None -> "" | Some max_msgs -> " " ^ string_of_int max_msgs)

let encode_ping () = "PING\r\n"
let encode_pong () = "PONG\r\n"

let encode_hpub ~subject ?reply_to ~headers payload =
  let headers = header_block headers in
  Printf.sprintf "HPUB %s%s %d %d\r\n%s%s\r\n" subject
    (match reply_to with None -> "" | Some reply_to -> " " ^ reply_to)
    (String.length headers)
    (String.length headers + String.length payload)
    headers payload

let invalid what = invalid_arg what

let parse_err line =
  let len = String.length line in
  if len >= 8 && String.sub line 0 6 = "-ERR '" && String.get line (len - 1) = '\''
  then String.sub line 6 (len - 7)
  else invalid "invalid -ERR line"

let parse_info line =
  let prefix = "INFO " in
  let json =
    String.sub line (String.length prefix) (String.length line - String.length prefix)
    |> Yojson.Safe.from_string
  in
  let fields =
    match json with
    | `Assoc fields -> fields
    | _ -> invalid "invalid INFO json"
  in
  let member name = List.assoc_opt name fields in
  let require name convert =
    match member name with
    | Some value -> convert value
    | None -> invalid ("missing INFO field: " ^ name)
  in
  let optional name convert =
    match member name with
    | None -> None
    | Some value -> Some (convert value)
  in
  let default name convert default =
    match member name with
    | None -> default
    | Some value -> convert value
  in
  let string = function `String value -> value | _ -> invalid "invalid INFO string" in
  let int = function
    | `Int value -> value
    | `Intlit value -> int_of_string value
    | _ -> invalid "invalid INFO int"
  in
  let bool = function `Bool value -> value | _ -> invalid "invalid INFO bool" in
  let string_list = function
    | `List values -> List.map string values
    | _ -> invalid "invalid INFO string list"
  in
  {
    server_id = require "server_id" string;
    server_name = optional "server_name" string;
    version = require "version" string;
    go = optional "go" string;
    host = require "host" string;
    port = require "port" int;
    headers = default "headers" bool false;
    max_payload = require "max_payload" int;
    proto = default "proto" int 0;
    client_id = optional "client_id" int;
    auth_required = default "auth_required" bool false;
    tls_required = default "tls_required" bool false;
    tls_verify = default "tls_verify" bool false;
    tls_available = default "tls_available" bool false;
    connect_urls = default "connect_urls" string_list [];
    ws_connect_urls = default "ws_connect_urls" string_list [];
    ldm = default "ldm" bool false;
    git_commit = optional "git_commit" string;
    jetstream = default "jetstream" bool false;
    ip = optional "ip" string;
    client_ip = optional "client_ip" string;
    nonce = optional "nonce" string;
    cluster = optional "cluster" string;
    domain = optional "domain" string;
  }

let parse_msg_meta line =
  match String.split_on_char ' ' line with
  | [ "MSG"; subject; sid; payload_size ] ->
      { subject; sid; reply_to = None; payload_size = int_of_string payload_size }
  | [ "MSG"; subject; sid; reply_to; payload_size ] ->
      {
        subject;
        sid;
        reply_to = Some reply_to;
        payload_size = int_of_string payload_size;
      }
  | _ -> invalid "invalid MSG line"

let parse_hmsg_meta line =
  match String.split_on_char ' ' line with
  | [ "HMSG"; subject; sid; header_size; total_size ] ->
      {
        subject;
        sid;
        reply_to = None;
        header_size = int_of_string header_size;
        total_size = int_of_string total_size;
      }
  | [ "HMSG"; subject; sid; reply_to; header_size; total_size ] ->
      {
        subject;
        sid;
        reply_to = Some reply_to;
        header_size = int_of_string header_size;
        total_size = int_of_string total_size;
      }
  | _ -> invalid "invalid HMSG line"

let parse_server_line = function
  | "PING" -> Ping
  | "PONG" -> Pong
  | "+OK" -> Ok
  | line when String.starts_with ~prefix:"-ERR " line -> Err (parse_err line)
  | line when String.starts_with ~prefix:"INFO " line -> Info (parse_info line)
  | line when String.starts_with ~prefix:"HMSG " line -> Hmsg_meta (parse_hmsg_meta line)
  | line when String.starts_with ~prefix:"MSG " line -> Msg_meta (parse_msg_meta line)
  | _ -> invalid "unknown server line"
