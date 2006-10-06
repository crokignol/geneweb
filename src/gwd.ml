(* camlp4r pa_extend.cmo ./pa_html.cmo ./pa_lock.cmo *)
(* $Id: gwd.ml,v 5.8 2006-10-06 12:14:25 ddr Exp $ *)
(* Copyright (c) 1998-2006 INRIA *)

open Config;
open Def;
open Gutil;
open Mutil;
open Printf;
open Util;

value green_color = "#2f6400";
value selected_addr = ref None;
value selected_port = ref 2317;
value redirected_addr = ref None;
value wizard_passwd = ref "";
value friend_passwd = ref "";
value wizard_just_friend = ref False;
value only_addresses = ref [];
value cgi = ref False;
value default_lang = ref "fr";
value setup_link = ref False;
value choose_browser_lang = ref False;
value images_dir = ref "";
value log_file = ref "";
value log_flags =
  [Open_wronly; Open_append; Open_creat; Open_text; Open_nonblock]
;
IFDEF UNIX THEN
value max_clients = ref None
END;
value robot_xcl = ref None;
value auth_file = ref "";
value daemon = ref False;
value login_timeout = ref 1800;
value conn_timeout = ref 120;
value trace_failed_passwd = ref False;

value log_oc () =
  if log_file.val <> "" then
    try open_out_gen log_flags 0o644 log_file.val with
    [ Sys_error _ -> do { log_file.val := ""; stderr } ]
  else stderr
;

value flush_log oc = if log_file.val <> "" then close_out oc else flush oc;

value is_multipart_form =
  let s = "multipart/form-data" in
  fun content_type ->
    let rec loop i =
      if i >= String.length content_type then False
      else if i >= String.length s then True
      else if content_type.[i] == Char.lowercase s.[i] then loop (i + 1)
      else False
    in
    loop 0
;

value extract_boundary content_type =
  let e = Util.create_env content_type in List.assoc "boundary" e
;

value fprintf_date oc tm =
  fprintf oc "%4d-%02d-%02d %02d:%02d:%02d" (1900 + tm.Unix.tm_year)
    (succ tm.Unix.tm_mon) tm.Unix.tm_mday tm.Unix.tm_hour tm.Unix.tm_min
    tm.Unix.tm_sec
;

value print_and_cut_if_too_big oc str =
  loop 0 where rec loop i =
    if i < String.length str then do {
      output_char oc str.[i];
      let i =
        if i > 700 && String.length str - i > 750 then do {
          fprintf oc " ... "; String.length str - 700
        }
        else i + 1
      in
      loop i
    }
    else ()
;

value log oc tm conf from gauth request script_name contents =
  let referer = Wserver.extract_param "referer: " '\n' request in
  let user_agent = Wserver.extract_param "user-agent: " '\n' request in
  do {
    let tm = Unix.localtime tm in
    fprintf_date oc tm;
    fprintf oc " (%d)" (Unix.getpid ());
    fprintf oc " %s?" script_name;
    print_and_cut_if_too_big oc contents;
    output_char oc '\n';
    fprintf oc "  From: %s\n" from;
    if gauth <> "" then fprintf oc "  User: %s\n" gauth else ();
    if conf.wizard && not conf.friend then
      fprintf oc "  User: %s%s(wizard)\n" conf.user
        (if conf.user = "" then "" else " ")
    else if conf.friend && not conf.wizard then
      fprintf oc "  User: %s%s(friend)\n" conf.user
        (if conf.user = "" then "" else " ")
    else ();
    if user_agent <> "" then fprintf oc "  Agent: %s\n" user_agent
    else ();
    if referer <> "" then do {
      fprintf oc "  Referer: ";
      print_and_cut_if_too_big oc referer;
      fprintf oc "\n"
    }
    else ();
  }
;

value log_passwd_failed passwd uauth oc tm from request base_file =
  let referer = Wserver.extract_param "referer: " '\n' request in
  let user_agent = Wserver.extract_param "user-agent: " '\n' request in
  do {
    let tm = Unix.localtime tm in fprintf_date oc tm;
    fprintf oc " (%d)" (Unix.getpid ());
    fprintf oc " %s_%s" base_file passwd;
    fprintf oc " => failed";
    if trace_failed_passwd.val then
      fprintf oc " (%s)" (String.escaped uauth)
    else ();
    fprintf oc "\n";
    fprintf oc "  From: %s\n" from;
    fprintf oc "  Agent: %s\n" user_agent;
    if referer <> "" then fprintf oc "  Referer: %s\n" referer else ();
  }
;

value copy_file fname =
  match Util.open_etc_file fname with
  [ Some ic ->
      do {
        try
          while True do { let c = input_char ic in Wserver.wprint "%c" c }
        with _ ->
          ();
        close_in ic;
        True
      }
  | None -> False ]
;

value http answer =
  do {
    Wserver.http answer;
    Wserver.wprint "Content-type: text/html; charset=iso-8859-1";
  }
;

value robots_txt () =
  let oc = log_oc () in
  do {
    Printf.fprintf oc "Robot request\n";
    flush_log oc;
    Wserver.http "";
    Wserver.wprint "Content-type: text/plain"; Util.nl (); Util.nl ();
    if copy_file "robots" then ()
    else do {
      Wserver.wprint "User-Agent: *"; nl ();
      Wserver.wprint "Disallow: /"; nl ();
    }
  }
;

value refuse_log from cgi =
  let oc = Secure.open_out_gen log_flags 0o644 "refuse_log" in
  do {
    let tm = Unix.localtime (Unix.time ()) in
    fprintf_date oc tm;
    fprintf oc " excluded: %s\n" from;
    close_out oc;
    if not cgi then http "403 Forbidden" else ();
    Wserver.wprint "Content-type: text/html";
    Util.nl ();
    Util.nl ();
    Wserver.wprint "Your access has been disconnected by administrator.\n";
    let _ : bool = copy_file "refuse" in ();
  }
;

value only_log from cgi =
  let oc = log_oc () in
  do {
    let tm = Unix.localtime (Unix.time ()) in
    fprintf_date oc tm;
    fprintf oc " Connection refused from %s " from;
    fprintf oc "(only ";
    list_iter_first
      (fun first s -> fprintf oc "%s%s" (if not first then "," else "") s)
      only_addresses.val;
    fprintf oc ")\n";
    flush_log oc;
    if not cgi then http "" else ();
    Wserver.wprint "Content-type: text/html; charset=iso-8859-1";
    Util.nl ();
    Util.nl ();
    Wserver.wprint "<head><title>Invalid access</title></head>\n";
    Wserver.wprint "<body><h1>Invalid access</h1></body>\n";
  }
;

value refuse_auth conf from auth auth_type =
  let oc = log_oc () in
  do {
    let tm = Unix.localtime (Unix.time ()) in
    fprintf_date oc tm;
    fprintf oc " Access failed\n";
    fprintf oc "  From: %s\n" from;
    fprintf oc "  Basic realm: %s\n" auth_type;
    fprintf oc "  Response: %s\n" auth;
    flush_log oc;
    Util.unauthorized conf auth_type;
  }
;

value index_from c s =
  loop where rec loop i =
    if i == String.length s then i else if s.[i] == c then i else loop (i + 1)
;

value index c s = index_from c s 0;

value rec extract_assoc key =
  fun
  [ [] -> ("", [])
  | [((k, v) as kv) :: kvl] ->
      if k = key then (v, kvl)
      else let (v, kvl) = extract_assoc key kvl in (v, [kv :: kvl]) ]
;

value input_lexicon lang =
  let ht = Hashtbl.create 501 in
  let fname = Filename.concat "lang" "lex_utf8.txt" in
  do {
    Gutil.input_lexicon lang ht
      (fun () -> Secure.open_in (Util.search_in_lang_path fname));
    ht
  }
;

value alias_lang lang =
  if String.length lang < 2 then lang
  else
    let fname =
      Util.search_in_lang_path (Filename.concat "lang" "alias_lg.txt")
    in
    match try Some (Secure.open_in fname) with [ Sys_error _ -> None ] with
    [ Some ic ->
        let lang =
          try
            let rec loop line =
              match Gutil.lindex line '=' with
              [ Some i ->
                  if lang = String.sub line 0 i then
                    String.sub line (i + 1) (String.length line - i - 1)
                  else loop (input_line ic)
              | None -> loop (input_line ic) ]
            in
            loop (input_line ic)
          with
          [ End_of_file -> lang ]
        in
        do { close_in ic; lang }
    | None -> lang ]
;

value rec cut_at_equal i s =
  if i = String.length s then (s, "")
  else if s.[i] == '=' then
    (String.sub s 0 i, String.sub s (succ i) (String.length s - succ i))
  else cut_at_equal (succ i) s
;

value strip_trailing_spaces s =
  let len =
    loop (String.length s) where rec loop len =
      if len = 0 then 0
      else
        match s.[len - 1] with
        [ ' ' | '\n' | '\r' | '\t' -> loop (len - 1)
        | _ -> len ]
  in
  String.sub s 0 len
;

value read_base_env cgi bname =
  let fname = Util.base_path [] (bname ^ ".gwf") in
  match try Some (Secure.open_in fname) with [ Sys_error _ -> None ] with
  [ Some ic ->
      let env =
        loop [] where rec loop env =
          match try Some (input_line ic) with [ End_of_file -> None ] with
          [ Some s ->
              let s = strip_trailing_spaces s in
              if s = "" || s.[0] = '#' then loop env
              else loop [cut_at_equal 0 s :: env]
          | None -> env ]
      in
      do { close_in ic; env }
  | None -> [] ]
;

value print_renamed conf new_n =
  let link () =
    let req = Util.get_request_string conf in
    let new_req =
      let len = String.length conf.bname in
      let rec loop i =
        if i > String.length req then ""
        else if i >= len && String.sub req (i - len) len = conf.bname then
          String.sub req 0 (i - len) ^ new_n ^
            String.sub req i (String.length req - i)
        else loop (i + 1)
      in
      loop 0
    in
    "http://" ^ Util.get_server_string conf ^ new_req
  in
  let env =
    [('o', fun _ -> conf.bname); ('e', fun _ -> new_n); ('l', link)]
  in
  match Util.open_etc_file "renamed" with
  [ Some ic ->
      do {
        Util.html conf;
        Util.nl ();
        Util.copy_from_etc env conf.lang conf.indep_command ic;
      }
  | None ->
      let title _ = Wserver.wprint "%s -&gt; %s" conf.bname new_n in
      do {
        Util.header conf title;
        let link = link () in
        tag "ul" begin
          Util.html_li conf;
          tag "a" "href=\"%s\"" link begin Wserver.wprint "%s" link; end;
        end;
        Util.trailer conf;
      } ]
;

value log_redirect conf from request req =
  let referer = Wserver.extract_param "referer: " '\n' request in
  lock_wait Srcfile.adm_file "gwd.lck" with
  [ Accept ->
      let oc = log_oc () in
      do {
        let tm = Unix.localtime (Unix.time ()) in
        fprintf_date oc tm;
        fprintf oc " %s\n" req;
        fprintf oc "  From: %s\n" from;
        fprintf oc "  Referer: %s\n" referer;
        flush_log oc;
      }
  | Refuse -> () ]
;

value print_redirected conf from request new_addr =
  let req = Util.get_request_string conf in
  let link = "http://" ^ new_addr ^ req in
  let env = [('l', fun _ -> link)] in
  do {
    log_redirect conf from request req;
    match Util.open_etc_file "redirect" with
    [ Some ic ->
        do {
          Util.html conf;
          Util.nl ();
          Util.copy_from_etc env conf.lang conf.indep_command ic;
        }
    | None ->
        let title _ = Wserver.wprint "Address changed" in
        do {
          Util.header conf title;
          Wserver.wprint "Use the following address:\n<p>\n";
          tag "ul" begin
            Util.html_li conf;
            stag "a" "href=\"%s\"" link begin Wserver.wprint "%s" link; end;
            Wserver.wprint "\n";
          end;
          Util.trailer conf;
        } ]
  }
;

value propose_base conf =
  let title _ = Wserver.wprint "Base" in
  do {
    Util.header conf title;
    tag "ul" begin
      Util.html_li conf;
      Wserver.wprint "<form method=\"get\" action=\"%s\">\n"
        conf.indep_command;
      Wserver.wprint "<input name=\"b\" size=\"40\"> =&gt;\n";
      Wserver.wprint "<input type=\"submit\" value=\"Ok\">\n";
    end;
    Util.trailer conf;
  }
;

value general_welcome conf =
  match Util.open_etc_file "index" with
  [ Some ic ->
      let env = [('w', fun _ -> Util.link_to_referer conf)] in
      do {
        Util.html conf;
        Util.nl ();
        Util.copy_from_etc env conf.lang conf.indep_command ic;
      }
  | None -> propose_base conf ]
;

value unauth_server conf passwd =
  let typ = if passwd = "w" then "Wizard" else "Friend" in
  do {
    Wserver.wprint "HTTP/1.0 401 Unauthorized"; Util.nl ();
    Wserver.wprint "WWW-Authenticate: Basic realm=\"%s %s\"" typ conf.bname;
    Util.nl ();
    Util.nl ();
    let url =
      conf.bname ^ "?" ^
        List.fold_left
          (fun s (k, v) ->
             if s = "" then k ^ "=" ^ v else s ^ "&" ^ k ^ "=" ^ v)
          "" conf.env
    in
    Wserver.wprint "\
<html><head>
<title>%s access failed for database %s</title>
</head>
" typ conf.bname;
    Wserver.wprint "<body><h1>%s access failed for database %s</h1>"
      typ conf.bname;
    Wserver.wprint "Return to <a href=\"%s\">welcome page</a>\n" url;
    Wserver.wprint "</body></html>\n";
  }
;

value match_auth_file auth_file uauth =
  if auth_file = "" then None
  else
    let auth_file = Util.base_path [] auth_file in
    match try Some (Secure.open_in auth_file) with [ Sys_error _ -> None ] with
    [ Some ic ->
        try
          let rec loop () =
            let line = input_line ic in
            let sauth = line in
            let (sauth, i) =
              try
                let i = String.index sauth ':' in
                let i =
                  try String.index_from sauth (i + 1) ':' with
                  [ Not_found -> String.length sauth ]
                in
                (String.sub sauth 0 i, i)
              with
              [ Not_found -> (uauth ^ "a" (* <> auth *), String.length sauth) ]
            in
            if uauth = sauth then
              do {
                close_in ic;
                let s =
                  if i = String.length line then ""
                  else
                    try
                      let j = String.index_from line (i + 1) ':' in
                      String.sub line (i + 1) (j - i - 1)
                    with
                    [ Not_found -> "" ]
                in
                let username =
                  try
                    let i = String.index s '/' in
                    let len = String.length s in
                    String.sub s 0 i ^ String.sub s (i + 1) (len - i - 1)
                  with
                  [ Not_found -> s ]
                in
                Some username
              }
            else loop ()
          in
          loop ()
        with
        [ End_of_file -> do { close_in ic; None } ]
    | None -> None ]
;

value match_simple_passwd sauth uauth =
  match lindex sauth ':' with
  [ Some _ -> sauth = uauth
  | None ->
      match lindex uauth ':' with
      [ Some i ->
          sauth = String.sub uauth (i + 1) (String.length uauth - i - 1)
      | None -> sauth = uauth ] ]
;

value match_auth passwd auth_file uauth =
  if passwd <> "" && match_simple_passwd passwd uauth then Some ""
  else match_auth_file auth_file uauth
;

type access_type =
  [ ATwizard of string | ATfriend of string | ATnormal | ATnone | ATset ]
;

value compatible_tokens check_from (addr1, base1_pw1) (addr2, base2_pw2) =
  (not check_from || addr1 = addr2) && base1_pw1 = base2_pw2
;

value get_actlog check_from utm from_addr base_password =
  let fname = Srcfile.adm_file "actlog" in
  match try Some (Secure.open_in fname) with [ Sys_error _ -> None ] with
  [ Some ic ->
      let tmout = float_of_int login_timeout.val in
      let rec loop changed r list =
        match try Some (input_line ic) with [ End_of_file -> None ] with
        [ Some line ->
            let i = index ' ' line in
            let tm = float_of_string (String.sub line 0 i) in
            let islash = index_from '/' line (i + 1) in
            let ispace = index_from ' ' line (islash + 1) in
            let addr = String.sub line (i + 1) (islash - i - 1) in
            let db_pwd = String.sub line (islash + 1) (ispace - islash - 1) in
            let c = line.[ispace + 1] in
            let user =
              let k = ispace + 3 in
              if k >= String.length line then ""
              else String.sub line k (String.length line - k)
            in
            let (list, r, changed) =
              if utm -. tm >= tmout then (list, r, True)
              else if
                compatible_tokens check_from (addr, db_pwd)
                  (from_addr, base_password)
              then
                let r = if c = 'w' then ATwizard user else ATfriend user in
                ([((from_addr, db_pwd), (utm, c, user)) :: list], r, True)
              else ([((addr, db_pwd), (tm, c, user)) :: list], r, changed)
            in
            loop changed r list
        | None ->
            do {
              close_in ic;
              let list =
                List.sort
                  (fun (_, (t1, _, _)) (_, (t2, _, _)) -> compare t2 t1)
                  list
              in
              (list, r, changed)
            } ]
      in
      loop False ATnormal []
  | None -> ([], ATnormal, False) ]
;

value set_actlog list =
  let fname = Srcfile.adm_file "actlog" in
  match try Some (Secure.open_out fname) with [ Sys_error _ -> None ] with
  [ Some oc ->
      do {
        List.iter
          (fun ((from, base_pw), (a, c, d)) ->
             fprintf oc "%.0f %s/%s %c%s\n" a from base_pw c
               (if d = "" then "" else " " ^ d))
          list;
        close_out oc;
      }
  | None -> () ]
;

value get_token check_from utm from_addr base_password =
  lock_wait Srcfile.adm_file "gwd.lck" with
  [ Accept ->
      let (list, r, changed) =
        get_actlog check_from utm from_addr base_password
      in
      do { if changed then set_actlog list else (); r }
  | Refuse -> ATnormal ]
;

value mkpasswd () =
  loop 0 where rec loop len =
    if len = 9 then Buff.get len
    else
      let v = Char.code 'a' + Random.int 26 in
      loop (Buff.store len (Char.chr v))
;

value random_self_init () =
  let seed = int_of_float (mod_float (Unix.time ()) (float max_int)) in
  Random.init seed
;

value set_token utm from_addr base_file acc user =
  lock_wait Srcfile.adm_file "gwd.lck" with
  [ Accept ->
      do {
        random_self_init ();
        let (list, _, _) = get_actlog False utm "" "" in
        let (x, xx) =
          let base = base_file ^ "_" in
          let rec loop ntimes =
            if ntimes = 0 then failwith "set_token"
            else
              let x = mkpasswd () in
              let xx = base ^ x in
              if List.exists
                   (fun (tok, _) ->
                      compatible_tokens False tok (from_addr, xx))
                   list
              then
                loop (ntimes - 1)
              else (x, xx)
          in
          loop 50
        in
        let list = [((from_addr, xx), (utm, acc, user)) :: list] in
        set_actlog list;
        x
      }
  | Refuse -> "" ]
;

value index_not_name s =
  loop 0 where rec loop i =
    if i == String.length s then i
    else
      match s.[i] with
      [ 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' -> loop (i + 1)
      | _ -> i ]
;

value print_request_failure cgi msg =
  do {
    if not cgi then http "" else ();
    Wserver.wprint "Content-type: text/html";
    Util.nl (); Util.nl ();
    Wserver.wprint "<head><title>Request failure</title></head>\n";
    Wserver.wprint "\
<body bgcolor=\"white\">
<h1 align=\"center\"><font color=\"red\">Request failure</font></h1>
The request could not be completed.<p>\n";
    Wserver.wprint "<em><font size=\"-1\">Internal message: %s</font></em>\n"
      msg;
    Wserver.wprint "</body>\n";
  }    
;

value refresh_url cgi request s i =
  let url =
    let serv = "http://" ^ Util.get_server_string_aux cgi request in
    let req =
      let bname = String.sub s 0 i in
      let str = Util.get_request_string_aux cgi request in
      if cgi then
        let cginame = String.sub str 0 (String.index str '?') in
        cginame ^ "?b=" ^ bname
      else "/" ^ bname ^ "?"
    in
    serv ^ req
  in
  do {
    if not cgi then http "" else ();
    Wserver.wprint "Content-type: text/html";
    Util.nl ();
    Util.nl ();
    Wserver.wprint "\
<head>
<meta http-equiv=\"REFRESH\"
 content=\"1;URL=%s\">
</head>
<body>
<a href=\"%s\">%s</a>
</body>
" url url url;
    raise Exit
  }
;

value http_preferred_language request =
  let v = Wserver.extract_param "accept-language: " '\n' request in
  if v = "" then ""
  else
    let s = String.lowercase v in
    let list =
      loop [] 0 0 where rec loop list i len =
        if i == String.length s then List.rev [Buff.get len :: list]
        else if s.[i] = ',' then loop [Buff.get len :: list] (i + 1) 0
        else loop list (i + 1) (Buff.store len s.[i])
    in
    let list = List.map strip_spaces list in
    let rec loop =
      fun
      [ [lang :: list] ->
          if List.mem lang Version.available_languages then lang
          else if String.length lang = 5 then
            let blang = String.sub lang 0 2 in
            if List.mem blang Version.available_languages then blang
            else loop list
          else loop list
      | [] -> "" ]
    in
    loop list
;

value allowed_titles env base_env () =
  if p_getenv env "all_titles" = Some "on" then []
  else
    try
      let fname = List.assoc "allowed_titles_file" base_env in
      if fname = "" then []
      else
        let ic = Secure.open_in (Filename.concat (Secure.base_dir ()) fname) in
        let list = ref [] in
        do {
          try while True do { list.val := [input_line ic :: list.val]; } with
          [ End_of_file -> close_in ic ];
          list.val
        }
    with
    [ Not_found | Sys_error _ -> [] ]
;

value make_conf cgi from_addr (addr, request) script_name contents env =
  let utm = Unix.time () in
  let tm = Unix.localtime utm in
  let (command, base_file, passwd, env, access_type) =
    let (base_passwd, env) =
      let (x, env) = extract_assoc "b" env in
      if x <> "" || cgi then (x, env) else (script_name, env)
    in
    let ip = index '_' base_passwd in
    let base_file =
      let s = String.sub base_passwd 0 ip in
      let s =
        if Filename.check_suffix s ".gwb" then Filename.chop_suffix s ".gwb"
        else s
      in
      let i = index_not_name s in
      if i = String.length s then s
      else refresh_url cgi request s i
    in
    let (passwd, env, access_type) =
      let has_passwd = List.mem_assoc "w" env in
      let (x, env) = extract_assoc "w" env in
      if has_passwd then
        (x, env, if x = "w" || x = "f" then ATnone else ATset)
      else
        let passwd =
          if ip = String.length base_passwd then ""
          else
            String.sub base_passwd (ip + 1)
              (String.length base_passwd - ip - 1)
        in
        let access_type =
          match passwd with
          [ "" ->
             if not cgi then ATnone
             else
               let mode = try Sys.getenv "GW_MODE" with [ Not_found -> "" ] in
               let r_user =
                 try Sys.getenv "REMOTE_USER" with [ Not_found -> "" ]
               in
               match (mode, r_user) with
               [ (_, "") -> ATnone
               | ("F", u) -> ATfriend u
               | ("W", u) -> ATwizard u
               | _ -> ATnone ]                  
          | "w" | "f" -> ATnone
          | _ -> get_token True utm from_addr base_passwd ]
        in
        (passwd, env, access_type)
    in
    let passwd = Util.decode_varenv passwd in
    let command = script_name in
    (command, base_file, passwd, env, access_type)
  in
  let (lang, env) = extract_assoc "lang" env in
  let lang =
    if lang = "" && choose_browser_lang.val then
      http_preferred_language request
    else lang
  in
  let lang = alias_lang lang in
  let (from, env) =
    match extract_assoc "opt" env with
    [ ("from", env) -> ("from", env)
    | ("", env) -> ("", env)
    | (x, env) -> ("", [("opt", x) :: env]) ]
  in
  let (threshold_test, env) = extract_assoc "threshold" env in
  do {
    if threshold_test <> "" then
      RelationLink.threshold.val := int_of_string threshold_test
    else ();
    let (sleep, env) =
      let (x, env) = extract_assoc "sleep" env in
      (if x = "" then 0 else int_of_string x, env)
    in
    let base_env = read_base_env cgi base_file in
    let default_lang =
      try
        let x = List.assoc "default_lang" base_env in
        if x = "" then default_lang.val else x
      with
      [ Not_found -> default_lang.val ]
    in
    let lexicon = input_lexicon (if lang = "" then default_lang else lang) in
    let wizard_passwd =
      try List.assoc "wizard_passwd" base_env with
      [ Not_found -> wizard_passwd.val ]
    in
    let wizard_passwd_file =
      try List.assoc "wizard_passwd_file" base_env with [ Not_found -> "" ]
    in
    let friend_passwd =
      try List.assoc "friend_passwd" base_env with
      [ Not_found -> friend_passwd.val ]
    in
    let friend_passwd_file =
      try List.assoc "friend_passwd_file" base_env with [ Not_found -> "" ]
    in
    let wizard_just_friend =
      if wizard_just_friend.val then True
      else
        try List.assoc "wizard_just_friend" base_env = "yes" with
        [ Not_found -> False ]
    in
    let passwd1 =
      let auth = Wserver.extract_param "authorization: " '\r' request in
      if auth = "" then ""
      else
        let i = String.length "Basic " in
        Base64.decode (String.sub auth i (String.length auth - i))
    in
    let uauth = if passwd = "w" || passwd = "f" then passwd1 else passwd in
    let (ok, wizard, friend, username) =
      match access_type with
      [ ATwizard user -> (True, True, False, "")
      | ATfriend user -> (True, False, True, "")
      | ATnormal -> (True, False, False, "")
      | ATnone | ATset ->
          if not cgi && (passwd = "w" || passwd = "f") then
            if passwd = "w" then
              if wizard_passwd = "" && wizard_passwd_file = "" then
                (True, True, friend_passwd = "", "")
              else
                match match_auth wizard_passwd wizard_passwd_file uauth with
                [ Some username -> (True, True, False, username)
                | None -> (False, False, False, "") ]
            else if passwd = "f" then
              if friend_passwd = "" && friend_passwd_file = "" then
                (True, False, True, "")
              else
                match match_auth friend_passwd friend_passwd_file uauth with
                [ Some username -> (True, False, True, username)
                | None -> (False, False, False, "") ]
            else assert False
          else if wizard_passwd = "" && wizard_passwd_file = "" then
            (True, True, friend_passwd = "", "")
          else
             match match_auth wizard_passwd wizard_passwd_file uauth with
             [ Some username -> (True, True, False, username)
             | _ ->
                  if friend_passwd = "" && friend_passwd_file = "" then
                    (True, False, True, "")
                  else
                  match match_auth friend_passwd friend_passwd_file uauth with
                  [ Some username -> (True, False, True, username)
                  | None -> (True, False, False, "") ] ] ]
    in
    let user =
      match lindex uauth ':' with
      [ Some i ->
          let s = String.sub uauth 0 i in
          if s = wizard_passwd || s = friend_passwd then "" else s
      | None ->
          match access_type with
          [ ATwizard user -> user
          | ATfriend user -> user
          | _ -> "" ] ]
    in
    let (command, passwd) =
      match access_type with
      [ ATset ->
          if wizard then
            let pwd_id = set_token utm from_addr base_file 'w' user in
            if cgi then (command, pwd_id) else (base_file ^ "_" ^ pwd_id, "")
          else if friend then
            let pwd_id = set_token utm from_addr base_file 'f' user in
            if cgi then (command, pwd_id) else (base_file ^ "_" ^ pwd_id, "")
          else if cgi then (command, "")
          else (base_file, "")
      | ATnormal -> if cgi then (command, "") else (base_file, "")
      | _ ->
          if cgi then (command, passwd)
          else if passwd = "" then (base_file, "")
          else (base_file ^ "_" ^ passwd, passwd) ]
    in
    let passwd1 =
      match lindex passwd1 ':' with
      [ Some i -> String.sub passwd1 (i + 1) (String.length passwd1 - i - 1)
      | None -> passwd ]
    in
    let cancel_links =
      match Util.p_getenv env "cgl" with
      [ Some "on" -> True
      | _ -> False ]
    in
    let is_rtl =
      try Hashtbl.find lexicon " !dir" = "rtl" with [ Not_found -> False ]
    in
    let allowed_titles = Lazy.lazy_from_fun (allowed_titles env base_env) in
    let manitou =
      try user <> "" && List.assoc "manitou" base_env = user with
      [ Not_found -> False ]
    in
    let conf =
      {from = from_addr;
       manitou = manitou;
       wizard = wizard && not wizard_just_friend;
       friend = friend || wizard_just_friend && wizard;
       just_friend_wizard = wizard && wizard_just_friend;
       user = user; username = username;
       passwd = passwd1; cgi = cgi; command = command;
       indep_command = (if cgi then command else "geneweb") ^ "?";
       highlight =
         try List.assoc "highlight_color" base_env with
         [ Not_found -> green_color ];
       lang = if lang = "" then default_lang else lang;
       default_lang = default_lang;
       multi_parents =
         try List.assoc "multi_parents" base_env = "yes" with
         [ Not_found -> False ];
       can_send_image =
         try List.assoc "can_send_image" base_env <> "no" with
         [ Not_found -> True ];
       public_if_titles =
         try List.assoc "public_if_titles" base_env = "yes" with
         [ Not_found -> False ];
       public_if_no_date =
         try List.assoc "public_if_no_date" base_env = "yes" with
         [ Not_found -> False ];
       cancel_links = cancel_links;
       setup_link = setup_link.val;
       access_by_key =
         try List.assoc "access_by_key" base_env = "yes" with
         [ Not_found -> wizard && friend ];
       private_years =
         try int_of_string (List.assoc "private_years" base_env) with
         [ Not_found | Failure _ -> 150 ];
       hide_names =
         if wizard || friend then False
         else
           try List.assoc "hide_private_names" base_env = "yes" with
           [ Not_found -> False ];
       use_restrict =
         if wizard || friend then False
         else
           try List.assoc "use_restrict" base_env = "yes" with
           [ Not_found -> False ];
       no_image =
         if wizard || friend then False
         else
           try List.assoc "no_image_for_visitor" base_env = "yes" with
           [ Not_found -> False ];
       bname = base_file; env = env; senv = [];
       henv =
         (if not cgi then []
          else if passwd = "" then [("b", base_file)]
          else [("b", base_file ^ "_" ^ passwd)]) @
           (if lang = "" then [] else [("lang", lang)]) @
           (if from = "" then [] else [("opt", from)]);
       base_env = base_env;
       allowed_titles = allowed_titles;
       request = request; lexicon = lexicon;
       xhs =
         match p_getenv base_env "doctype" with
         [ Some "html-4.01" -> ""
         | _ -> " /" ];
       charset = "utf-8";
       is_rtl = is_rtl;
       left = if is_rtl then "right" else "left";
       right = if is_rtl then "left" else "right";
       auth_file =
         try
           let x = List.assoc "auth_file" base_env in
           if x = "" then auth_file.val else Util.base_path [] x
         with
         [ Not_found -> auth_file.val ];
       border =
         match Util.p_getint env "border" with
         [ Some i -> i
         | None -> 0 ];
       n_connect = None;
       today =
         {day = tm.Unix.tm_mday; month = succ tm.Unix.tm_mon;
          year = tm.Unix.tm_year + 1900; prec = Sure; delta = 0};
       today_wd = tm.Unix.tm_wday;
       time = (tm.Unix.tm_hour, tm.Unix.tm_min, tm.Unix.tm_sec);
       ctime = utm}
    in
    (conf, sleep, if not ok then Some (passwd, uauth) else None)
  }
;

value log_and_robot_check conf auth from request script_name contents =
  if conf.cgi && log_file.val = "" && robot_xcl.val = None then ()
  else
    let tm = Unix.time () in
    lock_wait Srcfile.adm_file "gwd.lck" with
    [ Accept ->
        let oc = log_oc () in
        do {
          try
            do {
              match robot_xcl.val with
              [ Some (cnt, sec) ->
                  let s = "suicide" in
                  let suicide = Util.p_getenv conf.env s <> None in
                  conf.n_connect :=
                    Some (Robot.check oc tm from cnt sec conf suicide)
              | _ -> () ];
              if conf.cgi && log_file.val = "" then ()
              else log oc tm conf from auth request script_name contents;
            }
          with e ->
            do { flush_log oc; raise e };
          flush_log oc;
        }
    | Refuse -> () ]
;

value is_robot from =
  lock_wait Srcfile.adm_file "gwd.lck" with
  [ Accept ->
      let (robxcl, _) = Robot.robot_excl () in
      try let _ = List.assoc from robxcl.Robot.excl in True with
      [ Not_found -> False ]
  | Refuse -> False ]
;

value auth_err request auth_file =
  if auth_file = "" then (False, "")
  else
    let auth = Wserver.extract_param "authorization: " '\r' request in
    if auth <> "" then
      match
        try Some (Secure.open_in auth_file) with [ Sys_error _ -> None ]
      with
      [ Some ic ->
          let auth =
            let i = String.length "Basic " in
            Base64.decode (String.sub auth i (String.length auth - i))
          in
          try
            let rec loop () =
              if auth = input_line ic then do {
                close_in ic;
                let s =
                  try
                    let i = String.rindex auth ':' in String.sub auth 0 i
                  with
                  [ Not_found -> "..." ]
                in
                (False, s)
              }
              else loop ()
            in
            loop ()
          with
          [ End_of_file -> do { close_in ic; (True, auth) } ]
      | _ -> (True, "(auth file '" ^ auth_file ^ "' not found)") ]
    else (True, "(authorization not provided)")
;

value no_access conf =
  let title _ = Wserver.wprint "Error" in
  do {
    Util.rheader conf title;
    Wserver.wprint "No access to this database in CGI mode\n";
    Util.trailer conf;
  }
;

value conf_and_connection cgi from (addr, request) script_name contents env =
  let (conf, sleep, passwd_err) =
    make_conf cgi from (addr, request) script_name contents env
  in
  match redirected_addr.val with
  [ Some addr -> print_redirected conf from request addr
  | None ->
      let (auth_err, auth) =
        if conf.auth_file = "" then (False, "")
        else if cgi then (True, "")
        else auth_err request conf.auth_file
      in
      let mode = Util.p_getenv conf.env "m" in
      do {
        if mode <> Some "IM" then
          let contents =
            if List.mem_assoc "log_pwd" env then "..." else contents
          in
          log_and_robot_check conf auth from request script_name contents
        else ();
        match (cgi, auth_err, passwd_err) with
        [ (True, True, _) ->
            if is_robot from then Robot.robot_error cgi from 0 0
            else no_access conf
        | (_, True, _) ->
            if is_robot from then Robot.robot_error cgi from 0 0
            else
              let auth_type =
                let x =
                  try List.assoc "auth_file" conf.base_env with
                  [ Not_found -> "" ]
                in
                if x = "" then "GeneWeb service" else "database " ^ conf.bname
              in
              refuse_auth conf from auth auth_type
        | (_, _, Some (passwd, uauth)) ->
            if is_robot from then Robot.robot_error cgi from 0 0
            else do {
              let tm = Unix.time () in
              lock_wait Srcfile.adm_file "gwd.lck" with
              [ Accept ->
                  let oc = log_oc () in
                  do {
                    log_passwd_failed passwd uauth oc tm from request
                      conf.bname;
                    flush_log oc;
                  }
              | Refuse -> () ];
              unauth_server conf passwd;
            }
        | _ ->
            match mode with
            [ Some "DOC" -> Doc.print conf
            | _ ->
               if conf.bname = "" then general_welcome conf
               else
                 match
                   try Some (List.assoc "renamed" conf.base_env) with
                   [ Not_found -> None ]
                 with
                 [ Some n when n <> "" -> print_renamed conf n
                 | _ ->
                     do {
                       Request.treat_request_on_base conf
                         (log_file.val, log_oc, flush_log);
                       if sleep > 0 then Unix.sleep sleep else ();
                     } ] ] ]
      } ]
;

value chop_extension name =
  loop (String.length name - 1) where rec loop i =
    if i < 0 then name
    else if name.[i] == '.' then String.sub name 0 i
    else if name.[i] == '/' then name
    else if name.[i] == '\\' then name
    else loop (i - 1)
;

value match_strings regexp s =
  loop 0 0 where rec loop i j =
    if i == String.length regexp && j == String.length s then True
    else if i == String.length regexp then False
    else if j == String.length s then False
    else if regexp.[i] = s.[j] then loop (i + 1) (j + 1)
    else if regexp.[i] = '*' then
      if i + 1 == String.length regexp then True
      else if regexp.[i + 1] = s.[j] then loop (i + 2) (j + 1)
      else loop i (j + 1)
    else False
;

value excluded from =
  let efname = chop_extension Sys.argv.(0) ^ ".xcl" in
  match try Some (open_in efname) with [ Sys_error _ -> None ] with
  [ Some ic ->
      let rec loop () =
        match try Some (input_line ic) with [ End_of_file -> None ] with
        [ Some line ->
            if match_strings line from then do { close_in ic; True }
            else loop ()
        | None -> do { close_in ic; False } ]
      in
      loop ()
  | None -> False ]
;

value image_request cgi script_name env =
  match (Util.p_getenv env "m", Util.p_getenv env "v") with
  [ (Some "IM", Some fname) ->
      let fname =
        if fname.[0] = '/' then String.sub fname 1 (String.length fname - 1)
        else fname
      in
      let fname = Filename.basename fname in
      let fname = Util.image_file_name fname in
      let _ = Image.print_image_file cgi fname in True
  | _ ->
      let s = script_name in
      if Util.start_with s 0 "images/" then
        let i = String.length "images/" in
        let fname = String.sub s i (String.length s - i) in
        let fname = Filename.basename fname in
        let fname = Util.image_file_name fname in
        let _ = Image.print_image_file cgi fname in
        True
      else False ]
;

value strip_quotes s =
  let i0 = if String.length s > 0 && s.[0] == '"' then 1 else 0 in
  let i1 =
    if String.length s > 0 && s.[String.length s - 1] == '"' then
      String.length s - 1
    else String.length s
  in
  String.sub s i0 (i1 - i0)
;

value extract_multipart boundary str =
  let rec skip_nl i =
    if i < String.length str && str.[i] == '\r' then skip_nl (i + 1)
    else if i < String.length str && str.[i] == '\n' then i + 1
    else i
  in
  let next_line i =
    let i = skip_nl i in
    let rec loop s i =
      if i == String.length str || str.[i] == '\n' || str.[i] == '\r' then
        (s, i)
      else loop (s ^ String.make 1 str.[i]) (i + 1)
    in
    loop "" i
  in
  let boundary = "--" ^ boundary in
  let rec loop i =
    if i == String.length str then []
    else
      let (s, i) = next_line i in
      if s = boundary then
        let (s, i) = next_line i in
        let s = String.lowercase s in
        let env = Util.create_env s in
        match (Util.p_getenv env "name", Util.p_getenv env "filename") with
        [ (Some var, Some filename) ->
            let var = strip_quotes var in
            let filename = strip_quotes filename in
            let i = skip_nl i in
            let i1 =
              loop i where rec loop i =
                if i < String.length str then
                  if i > String.length boundary &&
                     String.sub str (i - String.length boundary)
                       (String.length boundary) =
                       boundary then
                    i - String.length boundary
                  else loop (i + 1)
                else i
            in
            let v = String.sub str i (i1 - i) in
            [(var ^ "_name", filename); (var, v) :: loop i1]
        | (Some var, None) ->
            let var = strip_quotes var in
            let (s, i) = next_line i in
            if s = "" then let (s, i) = next_line i in [(var, s) :: loop i]
            else loop i
        | _ -> loop i ]
      else if s = boundary ^ "--" then []
      else loop i
  in
  let env = loop 0 in
  let (str, _) =
    List.fold_left
      (fun (str, sep) (v, x) ->
         if v = "file" then (str, sep) else (str ^ sep ^ v ^ "=" ^ x, ";"))
      ("", "") env
  in
  (str, env)
;

value build_env request contents =
  let content_type = Wserver.extract_param "content-type: " '\n' request in
  if is_multipart_form content_type then
    let boundary = extract_boundary content_type in
    let (str, env) = extract_multipart boundary contents in (str, env)
  else (contents, Util.create_env contents)
;

value connection cgi (addr, request) script_name contents =
  let from =
    match addr with
    [ Unix.ADDR_UNIX x -> x
    | Unix.ADDR_INET iaddr port ->
        try (Unix.gethostbyaddr iaddr).Unix.h_name with _ ->
          Unix.string_of_inet_addr iaddr ]
  in
  do {
    if not cgi && script_name = "robots.txt" then robots_txt ()
    else if excluded from then refuse_log from cgi
    else
      let accept =
        if only_addresses.val = [] then True
        else List.mem from only_addresses.val
      in
      if not accept then only_log from cgi
      else
        try
          let (contents, env) = build_env request contents in
          if image_request cgi script_name env then ()
          else
            conf_and_connection cgi from (addr, request) script_name contents
              env
        with
        [ Adef.Request_failure msg -> print_request_failure cgi msg
        | Exit -> () ];
    Wserver.wflush ();
  }
;

value null_reopen flags fd =
  IFDEF UNIX THEN do {
    let fd2 = Unix.openfile "/dev/null" flags 0 in
    Unix.dup2 fd2 fd;
    Unix.close fd2;
  }
  ELSE () END
;

IFDEF SYS_COMMAND THEN
value wserver_auto_call = ref False
END;

value geneweb_server () =
  let auto_call =
    IFDEF SYS_COMMAND THEN wserver_auto_call.val
    ELSE try let _ = Sys.getenv "WSERVER" in True with [ Not_found -> False ]
    END
  in
  do {
    if not auto_call then do {
      let hostn =
        match selected_addr.val with
        [ Some addr -> addr
        | None -> try Unix.gethostname () with _ -> "computer" ]
      in
      eprintf "GeneWeb %s - " Version.txt;
      eprintf "Copyright (c) 1998-2006 INRIA\n";
      if not daemon.val then do {
        eprintf "Possible addresses:";
        eprintf "
   http://localhost:%d/base
   http://127.0.0.1:%d/base
   http://%s:%d/base" selected_port.val selected_port.val hostn
          selected_port.val;
        eprintf "
where \"base\" is the name of the database
Type %s to stop the service
" "control C";
      }
      else ();
      flush stderr;
      if daemon.val then
        if Unix.fork () = 0 then do {
          Unix.close Unix.stdin;
          null_reopen [Unix.O_WRONLY] Unix.stdout;
          null_reopen [Unix.O_WRONLY] Unix.stderr;
        }
        else exit 0
      else ();
      try Unix.mkdir (Filename.concat Util.cnt_dir.val "cnt") 0o777 with
      [ Unix.Unix_error _ _ _ -> () ];
    }
    else ();
    Wserver.f selected_addr.val selected_port.val conn_timeout.val
      (IFDEF UNIX THEN max_clients.val ELSE None END) (connection False)
  }
;

value geneweb_cgi addr script_name contents =
  do {
    try Unix.mkdir (Filename.concat Util.cnt_dir.val "cnt") 0o755 with
    [ Unix.Unix_error _ _ _ -> () ];
    let add k x request =
      try
        let v = Sys.getenv x in
        if v = "" then raise Not_found
        else [k ^ ": " ^ v :: request]
      with
      [ Not_found -> request ]
    in
    let request = [] in
    let request = add "cookie" "HTTP_COOKIE" request in
    let request = add "content-type" "CONTENT_TYPE" request in
    let request = add "accept-language" "HTTP_ACCEPT_LANGUAGE" request in
    let request = add "referer" "HTTP_REFERER" request in
    let request = add "user-agent" "HTTP_USER_AGENT" request in
    connection True (Unix.ADDR_UNIX addr, request) script_name contents
  }
;

value read_input len =
  if len >= 0 then do {
    let buff = String.create len in really_input stdin buff 0 len; buff
  }
  else do {
    let buff = ref "" in
    try
      while True do { let l = input_line stdin in buff.val := buff.val ^ l }
    with
    [ End_of_file -> () ];
    buff.val
  }
;

value arg_parse_in_file fname speclist anonfun errmsg =
  match try Some (open_in fname) with [ Sys_error _ -> None ] with
  [ Some ic ->
      let list =
        let list = ref [] in
        do {
          try
            while True do {
              let line = input_line ic in
              if line <> "" then list.val := [line :: list.val] else ()
            }
          with
          [ End_of_file -> () ];
          close_in ic;
          List.rev list.val
        }
      in
      let list =
        match list with
        [ [x] -> arg_list_of_string x
        | _ -> list ]
      in
      Argl.parse_list speclist anonfun errmsg list
  | _ -> () ]
;

module G = Grammar.Make (struct value lexer = Plexer.make (); end);
value robot_xcl_arg = G.Entry.create "robot_xcl arg";
GEXTEND G
  robot_xcl_arg:
    [ [ cnt = INT; ","; sec = INT; EOI ->
          (int_of_string cnt, int_of_string sec) ] ]
  ;
END;

value robot_exclude_arg s =
  try
    robot_xcl.val :=
      Some (G.Entry.parse robot_xcl_arg (G.parsable (Stream.of_string s)))
  with
  [ Stdpp.Exc_located _ (Stream.Error _ | Token.Error _) ->
      do {
        eprintf "Bad use of option -robot_xcl\n";
        eprintf "Use option -help for usage.\n";
        flush Pervasives.stderr;
        exit 2
      } ]
;

value slashify s =
  let s1 = String.copy s in
  do {
    for i = 0 to String.length s - 1 do {
      s1.[i] :=
        match s.[i] with
        [ '\\' -> '/'
        | x -> x ]
    };
    s1
  }
;

value make_cnt_dir x =
  do {
    mkdir_p x;
    IFDEF WIN95 THEN do {
      Wserver.sock_in.val := Filename.concat x "gwd.sin";
      Wserver.sock_out.val := Filename.concat x "gwd.sou";
    }
    ELSE () END;
    Util.cnt_dir.val := x;
  }
;

value main () =
  do {
    IFDEF WIN95 THEN do {
      Wserver.sock_in.val := "gwd.sin"; Wserver.sock_out.val := "gwd.sou";
    }
    ELSE () END;
    let usage =
      "Usage: " ^ Filename.basename Sys.argv.(0) ^
      " [options] where options are:"
    in
    let speclist =
      [("-hd", Arg.String Util.add_lang_path,
        "<dir>\n       Directory where the directory lang is installed.");
       ("-dd", Arg.String Util.add_doc_path,
        "<dir>\n       Directory where the documentation is installed.");
       ("-bd", Arg.String Util.set_base_dir,
        "<dir>\n       Directory where the databases are installed.");
       ("-wd", Arg.String make_cnt_dir, "\
<dir>
       Directory for socket communication (Windows) and access count.");
       ("-cgi", Arg.Set cgi, "\n       Force cgi mode.");
       ("-images_url", Arg.String (fun x -> Util.images_url.val := x),
        "<url>\n       URL for GeneWeb images (default: gwd send them)");
       ("-images_dir", Arg.String (fun x -> images_dir.val := x), "\
<dir>
       Same than previous but directory name relative to current");
       ("-a", Arg.String (fun x -> selected_addr.val := Some x), "\
<address>
       Select a specific address (default = any address of this computer)");
       ("-p", Arg.Int (fun x -> selected_port.val := x),
        "<number>\n       Select a port number (default = " ^
          string_of_int selected_port.val ^ "); > 1024 for normal users.");
       ("-setup_link", Arg.Set setup_link,
        "\n       Display a link to local gwsetup in bottom of pages.");
       ("-allowed_tags",
        Arg.String (fun x -> Util.allowed_tags_file.val := x), "\
<file>
       HTML tags which are allowed to be displayed. One tag per line in file.");
       ("-wizard", Arg.String (fun x -> wizard_passwd.val := x), "\
<passwd>
       Set a wizard password: access to all dates and updating.");
       ("-friend", Arg.String (fun x -> friend_passwd.val := x),
        "<passwd>\n       Set a friend password: access to all dates.");
       ("-wjf", Arg.Set wizard_just_friend,
        "\n       Wizard just friend (permanently)");
       ("-lang", Arg.String (fun x -> default_lang.val := x),
        "<lang>\n       Set a default language (default: fr).");
       ("-blang", Arg.Set choose_browser_lang,
        "\n       Select the user browser language if any.");
       ("-only",
        Arg.String (fun x -> only_addresses.val := [x :: only_addresses.val]),
        "<address>\n       Only inet address accepted.");
       ("-auth", Arg.String (fun x -> auth_file.val := x), "\
<file>
       Authorization file to restrict access. The file must hold lines
       of the form \"user:password\".");
       ("-log", Arg.String (fun x -> log_file.val := x),
        "<file>\n       Redirect log trace to this file.");
       ("-robot_xcl", Arg.String robot_exclude_arg, "\
<cnt>,<sec>
       Exclude connections when more than <cnt> requests in <sec> seconds.");
       ("-min_disp_req", Arg.Int (fun x -> Robot.min_disp_req.val := x),
        "\n       Minimum number of requests in robot trace (default: " ^
        string_of_int Robot.min_disp_req.val ^ ")");
       ("-login_tmout", Arg.Int (fun x -> login_timeout.val := x), "\
<sec>
       Login timeout for entries with passwords in CGI mode (default " ^ string_of_int login_timeout.val ^ "\
s)"); ("-redirect", Arg.String (fun x -> redirected_addr.val := Some x), "\
<addr>
       Send a message to say that this service has been redirected to <addr>");
       ("-trace_failed_passwd", Arg.Set trace_failed_passwd,
        "\n       Print the failed passwords in log");
       ("-nolock", Arg.Set Lock.no_lock_flag,
        "\n       Do not lock files before writing.") ::
       IFDEF UNIX THEN
         [("-max_clients", Arg.Int (fun x -> max_clients.val := Some x), "\
<num>
       Max number of clients treated at the same time (default: no limit)
       (not cgi).");
          ("-conn_tmout", Arg.Int (fun x -> conn_timeout.val := x),
           "<sec>\n       Connection timeout (default " ^
             string_of_int conn_timeout.val ^ "s; 0 means no limit)");
          ("-daemon", Arg.Set daemon, "\n       Unix daemon mode.");
          ("-chwd", Arg.String (fun s -> Doc.notify_change_wdoc.val := s),
           "<comm>\n       Call command when wdoc changed")]
       ELSE
         [("-noproc", Arg.Set Wserver.noproc,
           "\n       Do not launch a process at each request.") ::
          IFDEF SYS_COMMAND THEN
            [("-wserver", Arg.String (fun _ -> wserver_auto_call.val := True),
              "\n       (internal feature)")]
          ELSE [] END]
       END]
    in
    let anonfun s = raise (Arg.Bad ("don't know what to do with " ^ s)) in
    IFDEF UNIX THEN
      default_lang.val :=
        let s = try Sys.getenv "LANG" with [ Not_found -> "" ] in
        if List.mem s Version.available_languages then s
        else
          let s = try Sys.getenv "LC_CTYPE" with [ Not_found -> "" ] in
          if String.length s >= 2 then
            let s = String.sub s 0 2 in
            if List.mem s Version.available_languages then s else "en"
          else "en"
    ELSE () END;
    arg_parse_in_file (chop_extension Sys.argv.(0) ^ ".arg") speclist anonfun
      usage;
    Argl.parse speclist anonfun usage;
    if images_dir.val <> "" then
      let abs_dir =
        let f =
          Util.search_in_lang_path
            (Filename.concat images_dir.val "gwback.jpg")
        in
        let d = Filename.dirname f in
        if Filename.is_relative d then Filename.concat (Sys.getcwd ()) d
        else d
      in
      Util.images_url.val := "file://" ^ slashify abs_dir
    else ();
    if Secure.doc_path () = [] then
      List.iter (fun d -> Util.add_doc_path (Filename.concat d "doc"))
        (List.rev (Secure.lang_path ()))
    else ();
    if Util.cnt_dir.val = Filename.current_dir_name then
      Util.cnt_dir.val := Secure.base_dir ()
    else ();
    let (query, cgi) =
      try (Sys.getenv "QUERY_STRING", True) with
      [ Not_found -> ("", cgi.val) ]
    in
    if cgi then
      let is_post =
        try Sys.getenv "REQUEST_METHOD" = "POST" with [ Not_found -> False ]
      in
      let query =
        if is_post then do {
          let len =
            try int_of_string (Sys.getenv "CONTENT_LENGTH") with
            [ Not_found -> -1 ]
          in
          set_binary_mode_in stdin True;
          read_input len
        }
        else query
      in
      let addr =
        try Sys.getenv "REMOTE_HOST" with
        [ Not_found -> try Sys.getenv "REMOTE_ADDR" with [ Not_found -> "" ] ]
      in
      let script =
        try Sys.getenv "SCRIPT_NAME" with [ Not_found -> Sys.argv.(0) ]
      in
      geneweb_cgi addr (Filename.basename script) query
    else geneweb_server ()
  }
;

value test_eacces_bind err fun_name =
  IFDEF UNIX THEN
    if err = Unix.EACCES && fun_name = "bind" then
      try
        do {
          eprintf "
Error: invalid access to the port %d: users port number less than 1024
are reserved to the system. Solution: do it as root or choose another port
number greater than 1024.
" selected_port.val;
          flush stderr;
          True
        }
      with
      [ Not_found -> False ]
    else False
  ELSE False END
;

value print_exc exc =
  match exc with
  [ Unix.Unix_error Unix.EADDRINUSE "bind" _ ->
      do {
        eprintf "\nError: ";
        eprintf "the port %d" selected_port.val;
        eprintf " \
is already used by another GeneWeb daemon
or by another program. Solution: kill the other program or launch
GeneWeb with another port number (option -p)
";
        flush stderr;
      }
  | Unix.Unix_error err fun_name arg ->
      if test_eacces_bind err fun_name then ()
      else do {
        prerr_string "\"";
        prerr_string fun_name;
        prerr_string "\" failed";
        if String.length arg > 0 then do {
          prerr_string " on \""; prerr_string arg; prerr_string "\""; ()
        }
        else ();
        prerr_string ": ";
        prerr_endline (Unix.error_message err);
        flush stderr;
      }
  | _ -> try Printexc.print raise exc with _ -> () ]
;

try main () with exc -> print_exc exc;
