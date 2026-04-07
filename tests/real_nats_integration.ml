(* End-to-end integration check against a real NATS server started outside the process. *)
open Core
open Async

let url () =
  match Sys.getenv "NATS_URL" with
  | Some value -> Uri.of_string value
  | None -> Uri.of_string "nats://127.0.0.1:4222"

let connect_or_fail uri =
  Clock_ns.with_timeout (Time_ns.Span.of_sec 5.)
    (Nats_client_async.connect (Some uri))
  >>= function
  | `Timeout ->
      failwithf "timed out connecting to %s" (Uri.to_string uri) ()
  | `Result client -> Deferred.return client

let expect_ok label = function
  | Ok value -> value
  | Error error ->
      failwithf "%s failed: %s" label (Error.to_string_hum error) ()

let read_message label reader =
  Clock_ns.with_timeout (Time_ns.Span.of_sec 5.) (Pipe.read reader)
  >>= function
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
  connect_or_fail uri
  >>= fun subscriber_client ->
  connect_or_fail uri
  >>= fun actor_client ->
  Monitor.protect
    ~finally:(fun () ->
      Nats_client_async.close actor_client
      >>= fun () -> Nats_client_async.close subscriber_client)
    (fun () ->
      let publish_subject = "integration.publish." ^ Nats_client.Sid.create 8 in
      let request_subject = "integration.request." ^ Nats_client.Sid.create 8 in
      let headers =
        Nats_client.Headers.empty
        |> Nats_client.Headers.add ~name:"X-Test-Id" ~value:publish_subject
      in
      Nats_client_async.subscribe subscriber_client ~subject:publish_subject ()
      >>= fun publish_subscription ->
      Nats_client_async.subscribe subscriber_client ~subject:request_subject ()
      >>= fun request_subscription ->
      let publish_subscription =
        expect_ok "publish subscription" publish_subscription
      in
      let request_subscription =
        expect_ok "request subscription" request_subscription
      in
      let rec reply_loop () =
        Pipe.read request_subscription.messages
        >>= function
        | `Eof -> Deferred.unit
        | `Ok message ->
            (match message.reply_to with
            | None -> Deferred.unit
            | Some reply_to ->
                Nats_client_async.publish subscriber_client ~subject:reply_to
                  ("reply:" ^ message.payload);
                Deferred.unit)
            >>= reply_loop
      in
      don't_wait_for (reply_loop ());
      Clock_ns.after (Time_ns.Span.of_ms 100.)
      >>= fun () ->
      Nats_client_async.publish actor_client ~subject:publish_subject ~headers
        "integration-payload";
      read_message "publish/subscribe" publish_subscription.messages
      >>= fun published_message ->
      let received_headers =
        published_message.headers
        |> Option.value ~default:Nats_client.Headers.empty
        |> Nats_client.Headers.to_list
      in
      if not (String.equal published_message.payload "integration-payload")
      then
        failwithf "unexpected published payload: %s" published_message.payload ();
      require_header received_headers ~name:"X-Test-Id" ~expected:publish_subject;
      Nats_client_async.request actor_client ~subject:request_subject
        ~timeout:(Time_ns.Span.of_sec 5.) "ping"
      >>= fun response ->
      let response = expect_ok "request/reply" response in
      if not (String.equal response "reply:ping")
      then failwithf "unexpected request response: %s" response ();
      printf "real NATS integration passed against %s\n" (Uri.to_string uri);
      Deferred.unit)

let () = Thread_safe.block_on_async_exn main
