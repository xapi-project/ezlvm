(*
 * Copyright (C) Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

open Common

let newline = Re_str.regexp_string "\n"
let whitespace = Re_str.regexp "[\n\r\t ]+"
let comma = Re_str.regexp_string ","

(* The rules for LV names from 'man lvm': *)
let legal_lv_char = function
| 'a'..'z' | 'A' .. 'Z' | '0' .. '9' | '+' | '_' | '.' | '-' -> true
| _ -> false

let illegal_lv_names = [ "."; ".."; "snapshot"; "pvmove" ]
let illegal_lv_substrings =
  List.map Re_str.regexp_string
  [ "_mlog"; "_mimage"; "_rimage"; "_tdata"; "_tmeta" ]

let mangle_lv_name x : string =
  if List.mem x illegal_lv_names (* hopeless *)
  then "unknown-volume"
  else begin
    (* Remove illegal characters *)
    let result = String.copy x in
    for i = 0 to String.length result - 1 do
      result.[i] <- if legal_lv_char result.[i] then result.[i] else '_'
    done;
    (* Remove illegal substrings *)
    let rec loop acc = function
    | [] -> acc
    | r :: rs -> loop (Re_str.global_replace r "_" acc) rs in
    loop result illegal_lv_substrings
  end

(* Parse the result of 'command --units b' *)
let parse_B x =
  let x' = String.length x in
  try
    assert (x.[x'-1] = 'B');
    let without_b = String.sub x 0 (x' - 1) in
    Int64.of_string without_b
  with _ ->
    failwith (Printf.sprintf "Couldn't parse size in B: '%s' (expected [\\d]+B)" x)

(* Parse the result of 'command --units m' *)
let parse_MiB x =
  let x' = String.length x in
  try
    assert (x.[x'-1] = 'm');
    let without_m = String.sub x 0 (x' - 1) in
    let before_dot =
      try
        let dot = String.index without_m '.' in
        String.sub without_m 0 dot
      with _ -> without_m in
    Int64.of_string before_dot
  with _ ->
    failwith (Printf.sprintf "Couldn't parse size in MiB: '%s' (expected [\\d]+m)" x)

let make_temp_volume () =
  let path = Filename.temp_file Sys.argv.(0) "volume" in
  ignore_string (Common.run "dd" [ "if=/dev/zero"; "of=" ^ path; "seek=1024"; "bs=1M"; "count=1"]);
  finally
    (fun () ->
      ignore_string (Common.run "losetup" [ "-f"; path ]);
      (* /dev/loop0: [fd00]:1973802 (/tmp/SR.createc04251volume) *)
      let line = Common.run "losetup" [ "-j"; path ] in
      try
        let i = String.index line ' ' in
        String.sub line 0 (i - 1)
      with e ->
        error "Failed to parse output of losetup -j: [%s]" line;
        ignore_string (Common.run "losetup" [ "-d"; path ]);
        failwith (Printf.sprintf "Failed to parse output of losetup -j: [%s]" line)
    ) (fun () -> rm_f path)

let remove_temp_volume volume =
  ignore_string (Common.run "losetup" [ "-d"; volume ])

let free_space_in_vg vg =
  Common.run "vgs" ["--noheadings"; "-o"; "vg_size"; vg; "--units"; "m"] 
  |> Re_str.split_delim whitespace
  |> List.filter (fun x -> x <> "")
  |> List.hd
  |> parse_MiB

let thin_pool_name = "ezlvm_thin_pool"

let thin_pool_create vg_name =
  let free_space = free_space_in_vg vg_name in
  (* let's arbitrarily use 80% of the free space for thin provisioning *)
  let size_mb = Int64.(to_string (mul (div free_space 5L) 4L)) in
  ignore_string (Common.run "lvcreate" [ "-L"; size_mb; "--thinpool"; thin_pool_name; vg_name ]) 

let vgcreate vg_name = function
  | [] -> failwith "I need at least 1 physical device to create a volume group"
  | d :: ds as devices ->
    List.iter
      (fun dev ->
        (* First destroy anything already on the device *)
        ignore_string (run "dd" [ "if=/dev/zero"; "of=" ^ dev; "bs=512"; "count=4" ]);
        ignore_string (run "pvcreate" [ "--metadatasize"; "10M"; dev ])
      ) devices;

    (* Create the VG on the first device *)
    ignore_string (run "vgcreate" [ vg_name; d ]);
    List.iter (fun dev -> ignore_string (run "vgextend" [ vg_name; dev ])) ds;
    ignore_string (run "vgchange" [ "-an"; vg_name ]);
    thin_pool_create vg_name

let vgremove vg_name =
  ignore_string (run "lvremove" [ "-f"; vg_name ^ "/" ^ thin_pool_name ]);
  ignore_string(run "vgremove" [ "-f"; vg_name ])

type lv = {
  name: string;
  size: int64;
}

let to_lines output = List.filter (fun x -> x <> "") (Re_str.split_delim newline output)

let lvs vg_name =
  Common.run "lvs" [ "-o"; "lv_name,lv_size"; "--units"; "b"; "--noheadings"; vg_name ]
  |> to_lines
  |> List.map
    (fun line ->
      match List.filter (fun x -> x <> "") (Re_str.split_delim whitespace line) with
      | [ x; y ] ->
        let size = parse_B y in
        { name = x; size }
      | _ ->
        debug "Couldn't parse the LV name/ size: [%s]" line;
        failwith (Printf.sprintf "Couldn't parse the LV name/ size: [%s]" line)
    )

(* If a volume already exists then we see this on stderr:
   'Logical volume "testvol" already exists in volume group' *)
let volume_already_exists = Re_str.regexp_string "already exists in volume group"
let find r string =
  try
    let (_: int) = Re_str.search_forward r string 0 in
    true
  with Not_found ->
    false

let lvcreate vg_name lv_name kind =
  let args = match kind with
  | `New bytes ->
    let size_mb = Int64.to_string (Int64.div (Int64.add 1048575L bytes) (1048576L)) in
    [ "-V"; size_mb ^ "m"; "-T"; vg_name ^ "/" ^ thin_pool_name; "-n" ]
  | `Snapshot name ->
    [ "-s"; vg_name ^ "/" ^ lv_name; "-n" ] in
  let lv_name = mangle_lv_name lv_name in
  let lv_name' = String.length lv_name in
  let rec retry attempts_remaining suffix =
    try
      let lv_name = if suffix = 0 then lv_name else lv_name ^ (string_of_int suffix) in
      ignore_string (Common.run "lvcreate" (args @ [ lv_name ]));
      lv_name
    with Common.Bad_exit(5, _, _, stdout, stderr) as e->
      if find volume_already_exists stderr then begin
        let largest_suffix =
          lvs vg_name
          |>  (List.map (fun lv -> lv.name))
          |>  (List.filter (startswith lv_name))
          |>  (List.map (fun x -> String.sub x lv_name' (String.length x - lv_name')))
          |>  (List.map (fun x -> try int_of_string x with _ -> 0))
          |>  (List.fold_left max 0) in
        retry (attempts_remaining - 1) (largest_suffix + 1)
      end else raise e in
  retry 5 0

let lvremove vg_name lv_name =
  ignore_string(Common.run "lvremove" [ "-f"; Printf.sprintf "%s/%s" vg_name lv_name])

let device vg_name lv_name = Printf.sprintf "/dev/%s/%s" vg_name lv_name

let lvresize vg_name lv_name size =
  let size_mb = Int64.div (Int64.add 1048575L size) (1048576L) in
  (* Check it's not already the correct size *)
  let out = Common.run "lvdisplay" [ vg_name ^ "/" ^ lv_name; "-C"; "-o"; "size"; "--noheadings"; "--units"; "m"] in
  (* Returns something of the form: "   40.00M\n" *)
  let cur_mb =
    try
      String.index out '.'
      |> String.sub out 0               (* ignore the decimals *)
      |> Re_str.split_delim whitespace
      |> List.filter (fun x -> x <> "") (* get rid of whitespace *)
      |> List.hd                        (* there should be only one thing ... *)
      |> Int64.of_string                (* ... and it should be a number *)
    with e ->
      error "Couldn't parse the lvdisplay output: [%s]" out;
      raise e in
  let size_mb_rounded = Int64.mul 4L (Int64.div (Int64.add size_mb 3L) 4L) in
  if cur_mb <> size_mb_rounded then begin
    debug "lvresize: current size is %Ld MiB <> requested size %Ld MiB (rounded from %Ld); resizing" cur_mb size_mb_rounded size_mb;
    ignore_string(Common.run ~stdin:"y\n" "lvresize" [ vg_name ^ "/" ^ lv_name; "-L"; Int64.to_string size_mb ])
  end

let vgs () =
  Common.run "vgs" [ "-o"; "name"; "--noheadings" ]
  |> to_lines
  |> List.map
    (fun line ->
      List.hd (List.filter (fun x -> x <> "") (Re_str.split_delim whitespace line))
    )

let dash = Re_str.regexp_string "-"
let path_of vg lv =
  let vg' = Re_str.split_delim dash vg in
  let lv' = Re_str.split_delim dash lv in
  "/dev/mapper/" ^ (String.concat "--" vg') ^ "-" ^ (String.concat "--" lv')

let volume_of_lv sr lv = {
  Storage.V.Types.key = lv.name;
  name = lv.name;
  description = "";
  read_write = true;
  uri = ["block://" ^ (path_of sr lv.name) ];
  virtual_size = lv.size;
}

