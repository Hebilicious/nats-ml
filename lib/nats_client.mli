module Headers : sig
  type t

  val empty : t
  val of_list : (string * string) list -> t
  val to_list : t -> (string * string) list
  val add : t -> name:string -> value:string -> t
end

module Protocol : sig
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

  val default_connect : connect
  val encode_connect : ?connect:connect -> unit -> string
  val encode_pub : subject:string -> ?reply_to:string -> string -> string
  val encode_hpub :
    subject:string -> ?reply_to:string -> headers:Headers.t -> string -> string
  val encode_sub :
    subject:string -> ?queue_group:string -> sid:string -> unit -> string
  val encode_unsub : sid:string -> ?max_msgs:int -> unit -> string
  val encode_ping : unit -> string
  val encode_pong : unit -> string
  val parse_server_line : string -> parsed_line
end

module Sid : sig
  type t = string

  val create : int -> t
end
