(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2021 OCamlPro SAS                                       *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the GNU Lesser General    *)
(*  Public License version 2.1, with the special exception on linking     *)
(*  described in the LICENSE.md file in the root directory.               *)
(*                                                                        *)
(*                                                                        *)
(**************************************************************************)

open Db_utils

let int32_of_string = Int32.of_string
let string_of_string s = s
let int64_of_string = Int64.of_string

let init = Updated.db_versions_hash

let with_dbh f x =
  let>>> dbh = () in
  f dbh x

module EVENTS : sig

  type t = {
    name : string ;
    args : string ;
    time : int64 ;
    tr_lt : int64 ;
  }

  val list :
    ?serial: int32 -> unit -> ( int32 * string * t ) list Lwt.t

  val add : msg_id: string -> t -> unit Lwt.t
  val mem : msg_id: string -> bool Lwt.t

end = struct

  type t = {
    name : string ;
    args : string ;
    time : int64 ;
    tr_lt : int64 ;
  }

  let list ?serial () =
    let>>> dbh = () in
    let> list =
      match serial with
      | None ->
          [%pgsql dbh
              "SELECT * FROM freeton_events ORDER BY serial DESC LIMIT 100" ]
      | Some serial ->
          [%pgsql dbh
              "SELECT * FROM freeton_events WHERE serial < $serial \
               ORDER BY serial DESC LIMIT 100" ]
    in
    let list = List.rev list in
    let list =
      List.rev_map (fun ( serial, msg_id, name, args, time, tr_lt ) ->
          serial, msg_id, { name ; args ; time ; tr_lt } ) list
    in
    Lwt.return list

  let add ~msg_id event =
    let>>> dbh = () in
    [%pgsql dbh
        "insert into freeton_events \
         (msg_id, event_name, event_args, time, tr_lt ) \
         values (${msg_id}, ${event.name}, ${event.args}, \
         ${event.time}, ${event.tr_lt} )"]

  let mem ~msg_id =
    let>>> dbh = () in
    let> res = [%pgsql dbh
        "select msg_id from freeton_events where msg_id = ${msg_id}"]
    in
    match res with
    | [] -> Lwt.return false
    | _ -> Lwt.return true

end

module TRANSACTIONS : sig

  type t = {
    tr_lt : int64 ;
    tr_id : string ;
    block_id : string ;
    json : string option ;
  }

  val add : tr_lt:int64 -> tr_id:string ->
    block_id:string -> json:string -> unit Lwt.t

  val list : ?before_lt:int64 -> ?json:bool -> unit -> t list Lwt.t

  end = struct

  type t = {
    tr_lt : int64 ;
    tr_id : string ;
    block_id : string ;
    json : string option ;
  }

  let add ~tr_lt ~tr_id ~block_id ~json =
    let>>> dbh = () in
    [%pgsql dbh
        "insert into freeton_transactions (tr_lt, tr_id, block_id, json) \
         values ($tr_lt, $tr_id, $block_id, $json)"]

  let list ?before_lt ?(json=false) () =
    let>>> dbh = () in
    match json with
    | true ->
        let> list =
          match before_lt with
          | Some tr_lt ->
              [%pgsql dbh
                  "SELECT * FROM freeton_transactions WHERE tr_lt < $tr_lt \
                   ORDER BY tr_lt DESC LIMIT 100" ]
          | None ->
              [%pgsql dbh
                  "SELECT * FROM freeton_transactions \
                   ORDER BY tr_lt DESC LIMIT 100" ]
        in
        let list =
          List.rev_map (fun ( tr_lt, tr_id, block_id, json ) ->
              { tr_lt ; tr_id ; block_id ; json = Some json }
            ) ( List.rev list)
        in
        Lwt.return list
    | false ->
        let> list =
          match before_lt with
          | Some tr_lt ->
              [%pgsql dbh
                  "SELECT tr_lt, tr_id, block_id \
                   FROM freeton_transactions WHERE tr_lt < $tr_lt \
                   ORDER BY tr_lt DESC LIMIT 100" ]
          | None ->
              [%pgsql dbh
                  "SELECT tr_lt, tr_id, block_id \
                   FROM freeton_transactions \
                   ORDER BY tr_lt DESC LIMIT 100" ]
        in
        let list =
          List.rev_map (fun ( tr_lt, tr_id, block_id ) ->
              { tr_lt ; tr_id ; block_id ; json = None }
            ) ( List.rev list)
        in
        Lwt.return list
end

module PIDS : sig

  val get : string -> int option Lwt.t
  val set : string -> int -> unit Lwt.t

end = struct

  let get name =
    let>>> dbh = () in
    let> res =
      [%pgsql dbh "SELECT pid FROM pids WHERE name = $name"]
    in
    match res with
    | [] -> Lwt.return_none
    | [ pid ] -> Lwt.return_some ( Int32.to_int pid )
    | _ -> assert false

  let set name pid =
    let pid = Int32.of_int pid in
    let> old_pid = get name in
    match old_pid with
    | None ->
        let>>> dbh = () in
        [%pgsql dbh "INSERT INTO pids (name, pid) VALUES ($name, $pid)"]
    | Some _pid ->
        let>>> dbh = () in
        [%pgsql dbh "UPDATE pids SET pid = $pid WHERE name = $name"]

end
