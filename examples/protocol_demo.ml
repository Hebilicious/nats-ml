open Core

(* Run a local server first:
   docker run --rm --name nats-server -p 4222:4222 nats:latest
*)

let () =
  let connect =
    {
      Nats_client.Protocol.default_connect with
      name = Some "nats-ml-example";
      headers = true;
    }
  in
  let headers =
    Nats_client.Headers.empty
    |> Nats_client.Headers.add ~name:"Nats-Msg-Id" ~value:"example-1"
  in
  printf "CONNECT:\n%s\n" (Nats_client.Protocol.encode_connect ~connect ());
  printf "HPUB:\n%s\n"
    (Nats_client.Protocol.encode_hpub ~subject:"examples.demo" ~headers "hello");
  match
    Nats_client.Protocol.parse_server_line
      {|INFO {"server_id":"srv","version":"2.10.0","host":"127.0.0.1","port":4222,"headers":true,"max_payload":1048576,"proto":1,"jetstream":true}|}
  with
  | Info info ->
      printf "Parsed INFO from %s:%d with headers=%b\n" info.host info.port
        info.headers
  | _ -> failwith "expected INFO"
