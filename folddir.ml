(* Copyright (C) 2008 Mauricio Fernandez <mfp@acm.org> http//eigenclass.org
 * See README.txt and LICENSE for the redistribution and modification terms *)

open Util
open Unix

module type IGNORE =
sig
  type t
  val init : string -> t
  val update : t -> base:string -> path:string -> t
  val is_ignored : ?debug:bool -> t -> string -> bool -> bool
end

let join a b = if a <> "" && b <> "" then a ^ "/" ^ b else a ^ b

type 'a fold_acc = Continue of 'a | Prune of 'a

module type S =
sig
  type ignore_info
  val fold_directory :
    ?debug:bool -> ?sorted:bool ->
    ('a -> string -> Unix.stats -> 'a fold_acc) -> 'a ->
    string -> ?ign_info:ignore_info -> string -> 'a
end

module Make(M : IGNORE) : S with type ignore_info = M.t =
struct
  type ignore_info = M.t

  let rec fold_directory ?(debug=false) ?(sorted=false) f acc base
                         ?(ign_info = M.init base) path =
    let readd d =
      let l = ref [] in
      try while true do l := readdir d :: !l done; assert false
      with End_of_file -> !l in
    let acc = ref acc in
    let ign_info = M.update ign_info ~base ~path in
    let dir = join base path in
      try
        do_finally (opendir dir) closedir
          (fun d ->
             List.iter
               (function
                    "." | ".." -> ()
                  | n ->
                      let path_without_base = join path n in
                      let stat = lstat (join base path_without_base) in
                      let n_is_dir = stat.st_kind = S_DIR in
                        if M.is_ignored ~debug ign_info n n_is_dir then
                          ()
                        else
                          match f !acc path_without_base stat with
                            | Continue x ->
                                acc := x;
                                if n_is_dir then
                                  acc := fold_directory ~debug ~sorted f
                                         ~ign_info !acc base path_without_base
                            | Prune x -> acc := x)
               (let l = readd d in if sorted then List.sort compare l else l));
        !acc
      with Unix.Unix_error _ -> !acc
end

module Ignore_none : IGNORE =
struct
  type t = unit
  let init _ = ()
  let update () ~base ~path = ()
  let is_ignored ?debug () _ _ = false
end

module Gitignore : IGNORE =
struct
  open Printf

  type glob_type = Accept | Deny
  (* Simple: no wildcards, no slash
   * Simple_local: leading slash, otherwise no slashes, no wildcards
   * Endswith: *whatever, no slashes
   * Endswith_local: *whatever, leading slash only
   * Startswith_local: whatever*, leading slash only
   * Noslash: wildcards, no slashes
   * Nowildcard: non-prefix slashes, no wildcards
   * Complex: non-prefix slashes, wildcards
   * *)
  type patt =
      Simple of string | Noslash of string
    | Complex of string | Simple_local of string
    | Endswith of string | Endswith_local of string
    | Startswith_local of string
    | Nowildcard of string * int
  type file_or_dir = File_Or_Dir | Dir_Only
  type glob = glob_type * (file_or_dir * patt)
  type t = (string * glob list) list

  external fnmatch : bool -> string -> string -> bool = "perform_fnmatch" "noalloc"

  let string_of_patt =
    let string_of_patt_fod = function
        Simple s | Noslash s | Complex s | Nowildcard (s, _) -> s
      | Simple_local s -> "/" ^ s
      | Endswith s -> "*" ^ s
      | Endswith_local s -> "/*" ^ s
      | Startswith_local s -> "/" ^ s ^ "*"
    in function
        (File_Or_Dir, p) -> string_of_patt_fod p
      | (Dir_Only, p) -> (string_of_patt_fod p) ^ "/"

  let has_wildcard s =
    let rec loop s i max =
      if i < max then
        match String.unsafe_get s i with
            '*' | '?' | '[' | '{' -> true
            | _ -> loop s (i+1) max
      else false
    in loop s 0 (String.length s)

  let suff1 s = String.sub s 1 (String.length s - 1)
  let pref1 s = String.sub s 0 (String.length s - 1)

  let patt_of_string s =
    let patt_of_string_fod s =
      try
        match String.rindex s '/' with
            0 ->
              let s = suff1 s in
                if not (has_wildcard s) then Simple_local s
                else
                  let suff = suff1 s in
                    if s.[0] = '*' && not (has_wildcard suff) then
                      Endswith_local suff
                    else
                      let pref = pref1 s in
                        if s.[String.length s - 1] = '*' && not (has_wildcard pref) then
                          Startswith_local pref
                        else
                          Complex s
          | _ ->
              if not (has_wildcard s) then
                let l = String.length s in
                  Nowildcard (s, if s.[0] = '/' then l - 1 else l)
              else
                Complex s
      with Not_found ->
        if s = "" then Simple s else
          let suff = suff1 s in
            if s.[0] = '*' && not (has_wildcard suff) then
              Endswith suff
            else if has_wildcard s then
              Noslash s
            else
              Simple s
    in match s.[String.length s - 1] with
        '/' -> (Dir_Only, patt_of_string_fod (pref1 s))
      |   _ -> (File_Or_Dir, patt_of_string_fod s)

  let glob_of_string s = match s.[0] with
      '!' -> (Accept, (patt_of_string (suff1 s)))
    | _ -> (Deny, patt_of_string s)

  let collect_globs l =
    let rec aux acc = function
        [] -> acc
      | line::tl ->
          if line = "" || line.[0] = '#' then aux acc tl
          else aux (glob_of_string line :: acc) tl
    in aux [] l

  let read_gitignore path =
    try
      collect_globs
        (do_finally (open_in (join path ".gitignore")) close_in
           (fun is ->
              let l = ref [] in
                try
                  while true do
                    l := input_line is :: !l
                  done;
                  assert false
                with End_of_file -> !l) )
    with Sys_error _ -> []

  let init path = []

  let update t ~base ~path =
     let rec remove_local = function
        [] -> []
      | ((_, (_, (Simple _ | Noslash _ | Complex _ | Endswith _ | Nowildcard _))) as x)::tl ->
          x :: remove_local tl
      | (_, (_, (Simple_local _ | Endswith_local _ | Startswith_local _)))::tl ->
          remove_local tl in
    let t = match t with
        (f, l)::tl -> (f, remove_local l)::tl
      | [] -> []
    in (Filename.basename path, read_gitignore (join base path)) :: t

  type path = { basename : string; length : int; full_name : string Lazy.t }

  let path_of_string s = { basename = s; length = String.length s; full_name = lazy s }

  let string_of_path p = Lazy.force p.full_name

  let path_length p = p.length

  let push pref p =
    { basename = p.basename; length = p.length + 1 + String.length pref;
      full_name = lazy (String.concat "/" [pref; string_of_path p]) }

  let basename p = p.basename

  let check_ending suff path =
    let fname = basename path in
    let l1 = String.length suff in
    let l2 = String.length fname in
      if l2 < l1 then false else strneq l1 suff 0 fname (l2 - l1)

  let check_start pref path =
    let fname = basename path in
    let l1 = String.length pref in
    let l2 = String.length fname in
      if l2 < l1 then false else
        strneq l1 pref 0 fname 0

  let glob_matches local fod_patt path isdir =
    let glob_matches_fod local patt path = match patt with
        Simple s -> s = basename path
      | Simple_local s -> if local then s = basename path else false
      | Endswith s -> check_ending s path
      | Endswith_local s -> if local then check_ending s path else false
      | Startswith_local s -> if local then check_start s path else false
      | Noslash s -> fnmatch false s (basename path)
      | Complex s -> fnmatch true s (string_of_path path)
      | Nowildcard (s, l) ->
          if l = path_length path then
            fnmatch true s (string_of_path path)
          else false
    in match fod_patt with
        (Dir_Only, patt) -> if isdir then glob_matches_fod local patt path else false
      | (File_Or_Dir, patt) -> glob_matches_fod local patt path

  let path_of_ign_info t = String.concat "/" (List.rev (List.map fst t))

  let is_ignored ?(debug=false) t fname isdir =
    let rec aux local path = function
      | [] -> false
      | (dname, globs)::tl as t ->
        let ign = List.fold_left
          (fun s (ty, patt) ->
            if glob_matches local patt path isdir then
              (match ty with
                  Accept ->
                    if debug then
                        eprintf "ACCEPT %S (matched %S) at %S\n"
                          (string_of_path path) (string_of_patt patt)
                          (path_of_ign_info t);
                    `Kept
                | Deny ->
                    if debug then
                        eprintf "DENY %S (matched %S) at %S\n"
                          (string_of_path path) (string_of_patt patt)
                          (path_of_ign_info t);
                    `Ignored)
            else s)
          `Dontknow globs
        in match ign with
          | `Dontknow -> aux false (push dname path) tl
          | `Ignored -> true
          | `Kept -> false
    in fname = ".git" || aux true (path_of_string fname) t
end
