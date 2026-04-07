open Core
open Async

type publish_result = [ `Queued | `Dropped ]

type subscription = {
  sid : Nats_client.Sid.t;
  subject : string;
  messages : Nats_client.Protocol.message Pipe.Reader.t;
}

type connection = {
  reader : Reader.t;
  writer : Writer.t;
}

type subscription_state = {
  subscription : subscription;
  queue_group : string option;
  pipe_writer : Nats_client.Protocol.message Pipe.Writer.t;
}

type live_client = {
  uri : Uri.t;
  connect : Nats_client.Protocol.connect;
  ping_interval : Time_ns.Span.t;
  ping_timeout : Time_ns.Span.t;
  reconnect_initial : Time_ns.Span.t;
  reconnect_max : Time_ns.Span.t;
  max_pending : int;
  subscriptions : (string, subscription_state) Hashtbl.t;
  pending : string Queue.t;
  mutable pending_signal : unit Ivar.t option;
  mutable connection : connection option;
  mutable reconnecting : bool;
  mutable closed : bool;
  mutable awaiting_pong_since : Time_ns.t option;
  connected : unit Ivar.t;
}

type client =
  | Disabled
  | Enabled of live_client

let pp_publish_result formatter = function
  | `Queued -> Format.pp_print_string formatter "`Queued"
  | `Dropped -> Format.pp_print_string formatter "`Dropped"

let strip_cr line =
  let length = String.length line in
  if length > 0 && Char.equal line.[length - 1] '\r'
  then String.sub line ~pos:0 ~len:(length - 1)
  else line

let wake_pending state =
  match state.pending_signal with
  | Some signal when not (Ivar.is_full signal) ->
      state.pending_signal <- None;
      Ivar.fill_if_empty signal ()
  | _ -> ()

let wait_for_pending state =
  if state.closed
  then Deferred.unit
  else
    match state.pending_signal with
    | Some signal -> Ivar.read signal
    | None ->
        let signal = Ivar.create () in
        state.pending_signal <- Some signal;
        Ivar.read signal

let send_raw connection raw =
  Writer.write connection.writer raw;
  Writer.flushed connection.writer

let send_result connection raw =
  Monitor.try_with (fun () -> send_raw connection raw)
  >>| function
  | Ok () -> Ok ()
  | Error exn -> Or_error.of_exn exn

let drop_pending state = Queue.clear state.pending

let negotiate_connect (connect : Nats_client.Protocol.connect)
    (info : Nats_client.Protocol.info) =
  if info.Nats_client.Protocol.headers
  then
    {
      connect with
      protocol = Int.max connect.protocol 1;
      headers = true;
    }
  else connect

let message_of_meta (meta : Nats_client.Protocol.msg_meta) payload :
    Nats_client.Protocol.message =
  {
    Nats_client.Protocol.subject = meta.Nats_client.Protocol.subject;
    sid = meta.sid;
    reply_to = meta.reply_to;
    payload;
    headers = None;
  }

let parse_header_block block =
  let lines = String.split_lines block in
  match lines with
  | "NATS/1.0" :: lines ->
      let rec loop acc = function
        | [] | "" :: _ -> Some (Nats_client.Headers.of_list (List.rev acc))
        | line :: rest -> (
            match String.lsplit2 line ~on:':' with
            | None -> None
            | Some (name, value) ->
                let value = String.lstrip value in
                loop ((name, value) :: acc) rest)
      in
      loop [] lines
  | _ -> None

let message_of_hmsg (meta : Nats_client.Protocol.hmsg_meta) raw :
    Nats_client.Protocol.message option =
  if meta.header_size > meta.total_size || meta.header_size < 0
  then None
  else
    let headers_block = String.sub raw ~pos:0 ~len:meta.header_size in
    let payload =
      String.sub raw ~pos:meta.header_size ~len:(meta.total_size - meta.header_size)
    in
    Option.map (parse_header_block headers_block) ~f:(fun headers ->
        {
          Nats_client.Protocol.subject = meta.subject;
          sid = meta.sid;
          reply_to = meta.reply_to;
          payload;
          headers = Some headers;
        })

let replay_subscriptions state =
  let items = Hashtbl.data state.subscriptions in
  Deferred.List.iter items ~how:`Sequential ~f:(fun { subscription; queue_group; _ } ->
      match state.connection with
      | None -> Deferred.unit
      | Some connection ->
          send_raw connection
            (Nats_client.Protocol.encode_sub ~subject:subscription.subject
               ?queue_group ~sid:subscription.sid ())
          >>= fun () -> Writer.flushed connection.writer)

let rec reset_connection state connection =
  match state.connection with
  | Some current when phys_equal current connection ->
      state.connection <- None;
      state.awaiting_pong_since <- None;
      drop_pending state;
      wake_pending state;
      don't_wait_for
        (Writer.close connection.writer >>= fun () -> Reader.close connection.reader);
      start_reconnect state
  | _ -> ()

and writer_loop state =
  if state.closed
  then Deferred.unit
  else if Queue.is_empty state.pending || Option.is_none state.connection
  then wait_for_pending state >>= fun () -> writer_loop state
  else
    let raw = Queue.dequeue_exn state.pending in
    (match state.connection with
    | None -> Deferred.unit
    | Some connection ->
        send_result connection raw
        >>| function
        | Ok () -> ()
        | Error _ -> reset_connection state connection)
    >>= fun () -> writer_loop state

and start_reconnect ?(immediate = false) state =
  if state.closed || state.reconnecting
  then ()
  else (
    state.reconnecting <- true;
    let rec loop delay =
      if state.closed
      then (
        state.reconnecting <- false;
        Deferred.unit)
      else
        (if Time_ns.Span.( > ) delay Time_ns.Span.zero
         then Clock_ns.after delay
         else Deferred.unit)
        >>= fun () ->
        if state.closed || Option.is_some state.connection
        then (
          state.reconnecting <- false;
          Deferred.unit)
        else (
          let host =
            Uri.host state.uri
            |> Option.value_exn ~message:"NATS URI must include a host"
          in
          let port = Uri.port state.uri |> Option.value ~default:4222 in
          let where =
            Tcp.Where_to_connect.of_host_and_port
              (Host_and_port.create ~host ~port)
          in
          Monitor.try_with (fun () ->
              Tcp.connect where
              >>= fun (_socket, reader, writer) ->
              Reader.read_line reader
              >>= function
              | `Eof -> failwith "unexpected EOF waiting for INFO"
              | `Ok line -> (
                  match
                    Nats_client.Protocol.parse_server_line (strip_cr line)
                  with
                  | Info info ->
                      let connection = { reader; writer } in
                      let connect = negotiate_connect state.connect info in
                      send_raw connection
                        (Nats_client.Protocol.encode_connect ~connect ())
                      >>= fun () -> Deferred.return connection
                  | _ -> failwith "expected INFO from server" ))
          >>= function
          | Ok connection ->
              state.connection <- Some connection;
              state.awaiting_pong_since <- None;
              state.reconnecting <- false;
              Ivar.fill_if_empty state.connected ();
              replay_subscriptions state
              >>= fun () ->
              wake_pending state;
              don't_wait_for (reader_loop state connection);
              Deferred.unit
          | Error _ ->
              let next_delay =
                if Time_ns.Span.equal delay Time_ns.Span.zero
                then state.reconnect_initial
                else
                  Time_ns.Span.min state.reconnect_max
                    (Time_ns.Span.scale delay 2.)
              in
              loop next_delay)
    in
    don't_wait_for (loop (if immediate then Time_ns.Span.zero else state.reconnect_initial)))

and handle_disconnect state connection =
  reset_connection state connection;
  Deferred.unit

and read_payload connection length =
  let buffer = Bytes.create length in
  Reader.really_read connection.reader buffer
  >>= function
  | `Ok -> Deferred.return (Some (Bytes.unsafe_to_string ~no_mutation_while_string_reachable:buffer))
  | `Eof _ -> Deferred.return None

and read_crlf connection =
  let buffer = Bytes.create 2 in
  Reader.really_read connection.reader buffer
  >>= function
  | `Ok -> Deferred.return true
  | `Eof _ -> Deferred.return false

and reader_loop state connection =
  Reader.read_line connection.reader
  >>= function
  | `Eof -> handle_disconnect state connection
  | `Ok line -> (
      match
        Nats_client.Protocol.parse_server_line (strip_cr line)
      with
      | Ping ->
          send_raw connection (Nats_client.Protocol.encode_pong ())
          >>= fun () -> reader_loop state connection
      | Pong ->
          state.awaiting_pong_since <- None;
          reader_loop state connection
      | Ok | Err _ | Info _ -> reader_loop state connection
      | Msg_meta meta ->
          read_payload connection meta.payload_size
          >>= (function
                | None -> handle_disconnect state connection
                | Some payload ->
                    read_crlf connection
                    >>= fun had_crlf ->
                    if not had_crlf
                    then handle_disconnect state connection
                    else (
                      match Hashtbl.find state.subscriptions meta.sid with
                      | None -> Deferred.unit
                      | Some { pipe_writer; _ } ->
                          Pipe.write_without_pushback_if_open pipe_writer
                            (message_of_meta meta payload);
                          Deferred.unit)
                    >>= fun () -> reader_loop state connection)
      | Hmsg_meta meta ->
          read_payload connection meta.total_size
          >>= (function
                | None -> handle_disconnect state connection
                | Some raw ->
                    read_crlf connection
                    >>= fun had_crlf ->
                    if not had_crlf
                    then handle_disconnect state connection
                    else (
                      match
                        Hashtbl.find state.subscriptions meta.sid,
                        message_of_hmsg meta raw
                      with
                      | Some { pipe_writer; _ }, Some message ->
                          Pipe.write_without_pushback_if_open pipe_writer message;
                          Deferred.unit
                      | None, _ | _, None -> Deferred.unit)
                    >>= fun () -> reader_loop state connection))

let rec ping_loop state =
  if state.closed
  then Deferred.unit
  else
    Clock_ns.after state.ping_interval
    >>= fun () ->
    if state.closed
    then Deferred.unit
    else (
      match state.connection with
      | None -> Deferred.unit
      | Some connection -> (
          match state.awaiting_pong_since with
          | Some since
            when Time_ns.Span.( >= )
                   (Time_ns.diff (Time_ns.now ()) since)
                   state.ping_timeout ->
              handle_disconnect state connection
          | _ ->
              state.awaiting_pong_since <- Some (Time_ns.now ());
              Writer.write connection.writer (Nats_client.Protocol.encode_ping ());
              Deferred.unit ))
    >>= fun () -> ping_loop state

let create_live ?(connect = Nats_client.Protocol.default_connect)
    ?(ping_interval = Time_ns.Span.of_sec 30.)
    ?(ping_timeout = Time_ns.Span.of_sec 60.)
    ?(reconnect_initial = Time_ns.Span.of_ms 100.)
    ?(reconnect_max = Time_ns.Span.of_sec 5.) uri =
  {
    uri;
    connect;
    ping_interval;
    ping_timeout;
    reconnect_initial;
    reconnect_max;
    max_pending = 1024;
    subscriptions = Hashtbl.create (module String);
    pending = Queue.create ();
    pending_signal = None;
    connection = None;
    reconnecting = false;
    closed = false;
    awaiting_pong_since = None;
    connected = Ivar.create ();
  }

let connect ?connect ?ping_interval ?ping_timeout ?reconnect_initial
    ?reconnect_max = function
  | None -> Deferred.return Disabled
  | Some uri ->
      let state =
        create_live ?connect ?ping_interval ?ping_timeout ?reconnect_initial
          ?reconnect_max uri
      in
      don't_wait_for (writer_loop state);
      don't_wait_for (ping_loop state);
      start_reconnect ~immediate:true state;
      Ivar.read state.connected >>| fun () -> Enabled state

let build_publish ~subject ?reply_to ?headers payload =
  match headers with
  | None -> Nats_client.Protocol.encode_pub ~subject ?reply_to payload
  | Some headers -> Nats_client.Protocol.encode_hpub ~subject ?reply_to ~headers payload

let publish_result client ~subject ?reply_to ?headers payload =
  match client with
  | Disabled -> `Dropped
  | Enabled state ->
      if state.closed
         || Option.is_none state.connection
         || Queue.length state.pending >= state.max_pending
      then `Dropped
      else (
        Queue.enqueue state.pending
          (build_publish ~subject ?reply_to ?headers payload);
        wake_pending state;
        `Queued)

let publish client ~subject ?reply_to ?headers payload =
  ignore (publish_result client ~subject ?reply_to ?headers payload : publish_result)

let publish_json client ~subject ?reply_to ?headers payload =
  publish client ~subject ?reply_to ?headers (Yojson.Safe.to_string payload)

let send_live state raw =
  match state.connection with
  | None -> Deferred.return (Or_error.error_string "nats unavailable")
  | Some connection ->
      send_result connection raw
      >>| function
      | Ok () as ok -> ok
      | Error _ as error ->
          reset_connection state connection;
          error

let subscribe client ~subject ?queue_group ?sid () =
  match client with
  | Disabled -> Deferred.return (Or_error.error_string "nats disabled")
  | Enabled state ->
      let sid = Option.value sid ~default:(Nats_client.Sid.create 12) in
      let pipe_reader, pipe_writer = Pipe.create () in
      let subscription = { sid; subject; messages = pipe_reader } in
      Hashtbl.set state.subscriptions ~key:sid
        ~data:{ subscription; queue_group; pipe_writer };
      (match state.connection with
      | None -> Deferred.return (Ok subscription)
      | Some _ ->
          send_live state
            (Nats_client.Protocol.encode_sub ~subject ?queue_group ~sid ())
          >>| Result.map ~f:(fun () -> subscription))

let unsubscribe client ?max_msgs sid =
  match client with
  | Disabled -> Deferred.return (Or_error.error_string "nats disabled")
  | Enabled state ->
      (match Hashtbl.find_and_remove state.subscriptions sid with
      | Some { pipe_writer; _ } -> Pipe.close pipe_writer
      | None -> ());
      (match state.connection with
      | None -> Deferred.return (Ok ())
      | Some _ ->
          send_live state
            (Nats_client.Protocol.encode_unsub ~sid ?max_msgs ()))

let request client ~subject ?headers ?timeout payload =
  match client with
  | Disabled -> Deferred.return (Or_error.error_string "nats disabled")
  | Enabled state ->
      if Option.is_none state.connection
      then Deferred.return (Or_error.error_string "nats unavailable")
      else
        let inbox = "_INBOX." ^ Nats_client.Sid.create 16 in
        let sid = Nats_client.Sid.create 12 in
        subscribe client ~subject:inbox ~sid ()
        >>= function
        | Error _ as error -> Deferred.return error
        | Ok subscription ->
            let await_message =
              Pipe.read subscription.messages
              >>| function
              | `Ok message -> Ok message.Nats_client.Protocol.payload
              | `Eof -> Or_error.error_string "request subscription closed"
            in
            Monitor.protect
              ~finally:(fun () -> unsubscribe client sid >>| ignore)
              (fun () ->
                send_live state
                  (build_publish ~subject ~reply_to:inbox ?headers payload)
                >>= function
                | Error _ as error -> Deferred.return error
                | Ok () -> (
                    match timeout with
                    | None -> await_message
                    | Some timeout ->
                        Clock_ns.with_timeout timeout await_message
                        >>| function
                        | `Timeout -> Or_error.error_string "request timeout"
                        | `Result result -> result ))

let close = function
  | Disabled -> Deferred.unit
  | Enabled state ->
      let connection = state.connection in
      state.closed <- true;
      state.connection <- None;
      state.awaiting_pong_since <- None;
      drop_pending state;
      wake_pending state;
      Hashtbl.iter state.subscriptions ~f:(fun { pipe_writer; _ } ->
          Pipe.close pipe_writer);
      (match connection with
      | None -> Deferred.unit
      | Some connection ->
          Writer.close connection.writer >>= fun () -> Reader.close connection.reader)
