(** Runtime-independent NATS protocol primitives.

    This package exposes NATS protocol types, command encoders, server line
    parsers, headers, and subscription id helpers. It does not open network
    connections by itself.

    For an Async-based client that uses these protocol primitives, see the
    [nats-client-async] package. *)

(** Ordered NATS headers.

    Header order and duplicate header names are preserved. *)

module Headers : sig
  type t
  (** A collection of headers. *)

  val empty : t
  (** The empty header collection. *)

  val of_list : (string * string) list -> t
  (** Build headers from name/value pairs.

      The order returned by [to_list] matches the order supplied here. *)

  val to_list : t -> (string * string) list
  (** Return headers as name/value pairs in insertion order. *)

  val add : t -> name:string -> value:string -> t
  (** Add one header value. Duplicate names are allowed. *)
end

(** NATS protocol frames and server line parsing. *)
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
  (** Client options encoded in the initial [CONNECT] command. *)

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
  (** Server metadata advertised by an [INFO] line. *)

  type msg_meta = {
    subject : string;
    sid : string;
    reply_to : string option;
    payload_size : int;
  }
  (** Metadata parsed from a [MSG] line.

      The payload bytes are read separately by the runtime client. *)

  type hmsg_meta = {
    subject : string;
    sid : string;
    reply_to : string option;
    header_size : int;
    total_size : int;
  }
  (** Metadata parsed from an [HMSG] line.

      [header_size] is the size of the NATS header block. [total_size] is the
      combined size of the header block and payload. *)

  type message = {
    subject : string;
    sid : string;
    reply_to : string option;
    payload : string;
    headers : Headers.t option;
  }
  (** A complete message after its payload, and optional headers, have been read. *)

  type parsed_line =
    | Ping
    | Pong
    | Ok
    | Err of string
    | Info of info
    | Msg_meta of msg_meta
    | Hmsg_meta of hmsg_meta
  (** A server control line parsed without its trailing CRLF. *)

  val default_connect : connect
  (** Default [CONNECT] options. *)

  val encode_connect : ?connect:connect -> unit -> string
  (** Encode a [CONNECT] command, including the trailing CRLF. *)

  val encode_pub : subject:string -> ?reply_to:string -> string -> string
  (** Encode a [PUB] command with a payload. *)

  val encode_hpub :
    subject:string -> ?reply_to:string -> headers:Headers.t -> string -> string
  (** Encode an [HPUB] command with headers and a payload. *)

  val encode_sub :
    subject:string -> ?queue_group:string -> sid:string -> unit -> string
  (** Encode a [SUB] command. *)

  val encode_unsub : sid:string -> ?max_msgs:int -> unit -> string
  (** Encode an [UNSUB] command. [max_msgs] limits how many further messages the
      server may deliver before removing the subscription. *)

  val encode_ping : unit -> string
  (** Encode a [PING] command. *)

  val encode_pong : unit -> string
  (** Encode a [PONG] command. *)

  val parse_server_line : string -> parsed_line
  (** Parse one server line without the trailing CRLF.

      Raises [Invalid_argument] when the line is malformed or unsupported. *)
end

(** Subscription identifiers. *)
module Sid : sig
  type t = string
  (** A NATS subscription id. *)

  val create : int -> t
  (** Create a random alphanumeric subscription id with the requested length. *)
end
