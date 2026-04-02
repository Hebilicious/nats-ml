type t = string

let alphabet =
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

let create length =
  let limit = String.length alphabet in
  String.init length (fun _ -> String.get alphabet (Random.int limit))
