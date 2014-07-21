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

let write_lvm_conf dir devices =
  Unix.mkdir (Filename.concat dir "dev") 0o0755;
  Unix.mkdir (Filename.concat dir "cache") 0o0755;

  List.iter (fun device ->
    let dest = Filename.(concat (concat dir "dev") (basename device)) in
    rm_f dest;
    Unix.symlink device dest
  ) devices;

  let config = String.concat "\n" [
    "devices {";
    "dir=\"/dev\"";
    Printf.sprintf "scan=\"%s/dev\"" dir;
    "preferred_names=[]";
    "filter=[\"a|.*|\"]";
    Printf.sprintf "cache_dir=\"%s/cache\"" dir;
    "cache_file_prefix=\"\"";
    "write_cache_state=0";
    "sysfs_scan=0";
    "md_component_detection=0";
    "ignore_suspended_devices=0";
    "}";
    "activation {";
    "missing_stripe_filler=\"/dev/ioerror\"";
    "reserved_stack=256";
    "reserved_memory=8192";
    "process_priority=-18";
    "mirror_region_size=512";
    "readahead=\"auto\"";
    "mirror_log_fault_policy=\"allocate\"";
    "mirror_device_fault_policy=\"remove\"";
    "}";
    "global {";
    "umask=63";
    "test=0";
    "units=\"h\"";
    "activation=1";
    "proc=\"/proc\"";
    "locking_type=1";
    "fallback_to_clustered_locking=1";
    "fallback_to_local_locking=1";
    Printf.sprintf "locking_dir=\"%s/lock\"" dir;
    "}";
    "shell {";
    "history_size=100";
    "}";
    "backup {";
    "backup=1";
    Printf.sprintf "backup_dir=\"%s/backup\"" dir;
    "archive=0";
    Printf.sprintf "archive_dir=\"%s/archive\"" dir;
    "retain_min=10";
    "retain_days=30";
    "}";
    "log {";
    "verbose=0";
    "syslog=1";
    "overwrite=0";
    "level=0";
    "indent=1";
    "command_names=0";
    "prefix=\"  \"";
    "}"
  ] in
  file_of_string (Filename.concat dir "lvm.conf") config

(* Create a temporary LVM config directory *)
let make_tmp_dir () =
  let base = Filename.(concat (get_temp_dir_name ()) (basename Sys.argv.(0) ^ "." ^ (string_of_int (Unix.getpid ())))) in
  let rec loop count =
    let this = base ^ "." ^ (string_of_int count) in
    match (try Unix.mkdir this 0o0700; true with Unix.Unix_error(Unix.EEXIST, _, _) -> false) with
    | true -> this
    | false -> loop (count + 1) in
  loop 0

(* When testing, we use private LVM configs. In normal operation we use the
   system LVM config *)
let test_devices = ref None

let run args = match !test_devices with
  | None -> run "lvm" args
  | Some devices ->
    let dir = make_tmp_dir () in
    write_lvm_conf dir devices;
    finally
      (fun () ->
        run ~env:[| "LVM_SYSTEM_DIR=" ^ dir |] "lvm" args
      ) (fun () -> run "rm" ["-rf"; dir])

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
