type t = (string * string) list

let empty = []
let of_list headers = List.rev headers
let to_list headers = List.rev headers
let add headers ~name ~value = (name, value) :: headers
