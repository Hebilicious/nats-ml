(* Minimal external consumer that links against the installed package and exercises it. *)
open Core
open Async

let url () =
  match Sys.getenv "NATS_URL" with
  | Some value -> Uri.of_string value
  | None -> Uri.of_string "nats://127.0.0.1:4222"

let connect_or_fail uri =
  let%bind result =
    Clock_ns.with_timeout (Time_ns.Span.of_sec 5.)
      (Nats_client_async.connect (Some uri))
  in
  match result with
  | `Timeout ->
      failwithf "timed out connecting to %s" (Uri.to_string uri) ()
  | `Result client -> Deferred.return client

let expect_ok label = function
  | Ok value -> value
  | Error error ->
      failwithf "%s failed: %s" label (Error.to_string_hum error) ()

let read_message label reader =
  let%bind result =
    Clock_ns.with_timeout (Time_ns.Span.of_sec 5.) (Pipe.read reader)
  in
  match result with
  | `Timeout -> failwithf "%s timed out waiting for a message" label ()
  | `Result `Eof -> failwithf "%s closed before delivering a message" label ()
  | `Result (`Ok message) -> Deferred.return message

let require_header headers ~name ~expected =
  match List.Assoc.find headers ~equal:String.equal name with
  | Some value when String.equal value expected -> ()
  | Some value ->
      failwithf "expected header %s=%s but received %s" name expected value ()
  | None -> failwithf "missing header %s" name ()

let main () =
  let uri = url () in
  let%bind subscriber_client = connect_or_fail uri in
  let%bind actor_client = connect_or_fail uri in
  Monitor.protect
    ~finally:(fun () ->
      let%bind () = Nats_client_async.close actor_client in
      Nats_client_async.close subscriber_client)
    (fun () ->
      let publish_subject = "consumer.publish." ^ Nats_client.Sid.create 8 in
      let request_subject = "consumer.request." ^ Nats_client.Sid.create 8 in
      let headers =
        Nats_client.Headers.empty
        |> Nats_client.Headers.add ~name:"X-Consumer" ~value:publish_subject
      in
      let%bind publish_subscription =
        Nats_client_async.subscribe subscriber_client ~subject:publish_subject ()
        >>| expect_ok "publish subscription"
      in
      let%bind request_subscription =
        Nats_client_async.subscribe subscriber_client ~subject:request_subject ()
        >>| expect_ok "request subscription"
      in
      let rec reply_loop () =
        let%bind next_message = Pipe.read request_subscription.messages in
        match next_message with
        | `Eof -> Deferred.unit
        | `Ok message ->
            (match message.reply_to with
            | None -> Deferred.unit
            | Some reply_to ->
                Nats_client_async.publish subscriber_client ~subject:reply_to
                  (sprintf "consumer-reply:%s" message.payload);
                Deferred.unit)
            >>= reply_loop
      in
      don't_wait_for (reply_loop ());
      let%bind () = Clock_ns.after (Time_ns.Span.of_ms 100.) in
      Nats_client_async.publish_json actor_client ~subject:publish_subject ~headers
        (`Assoc [ ("kind", `String "consumer"); ("runtime", `String "async") ]);
      let%bind published_message =
        read_message "consumer publish/subscribe" publish_subscription.messages
      in
      if
        not
          (String.equal published_message.payload
             {|{"kind":"consumer","runtime":"async"}|})
      then
        failwithf "unexpected JSON payload: %s" published_message.payload ();
      let received_headers =
        published_message.headers
        |> Option.value ~default:Nats_client.Headers.empty
        |> Nats_client.Headers.to_list
      in
      require_header received_headers ~name:"X-Consumer" ~expected:publish_subject;
      let%bind response =
        Nats_client_async.request actor_client ~subject:request_subject
          ~timeout:(Time_ns.Span.of_sec 5.) "ping"
      in
      let response = expect_ok "consumer request/reply" response in
      if not (String.equal response "consumer-reply:ping")
      then failwithf "unexpected consumer request response: %s" response ();
      printf "consumer fixture passed against %s\n" (Uri.to_string uri);
      Deferred.unit)

let () = Thread_safe.block_on_async_exn main
