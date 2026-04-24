# bmkg.tcl
# Eggdrop TCL + PostgreSQL + curl BMKG web utama
# Command:
#   !cuaca <lokasi>
# Contoh:
#   !cuaca jaktim
#   !cuaca jakarta selatan
#   !cuaca bekasi
#   !cuaca bali

bind pub - !cuaca bmkg_pub
bind msg - !cuaca bmkg_msg

# =========================
# CONFIG
# =========================
set bmkg(psql) "/usr/bin/psql"
set bmkg(curl) "/usr/bin/curl"

set bmkg(db_host) "127.0.0.1"
set bmkg(db_name) "wilayah_indonesia"
set bmkg(db_user) "bmkgbot"
set bmkg(db_pass) "gantipasswordku"

set bmkg(curl_timeout) 25
set bmkg(debug) 0
set bmkg(debug_target) "#fyp"

# =========================
# DEBUG
# =========================
proc bmkg_log {msg} {
    global bmkg
    if {[info exists bmkg(debug)] && $bmkg(debug)} {
        putserv "PRIVMSG $bmkg(debug_target) :BMKG DEBUG: $msg"
        putlog "BMKG DEBUG: $msg"
    }
}

# =========================
# UTIL
# =========================
proc bmkg_trim {s} {
    regsub -all {[ \t\r\n]+} [string trim $s] { } s
    return $s
}
proc bmkg_htmldecode {s} {
    set s [string map {
        "&nbsp;" " "
        "&amp;" "&"
        "&quot;" "\""
        "&#x27;" "'"
        "&#39;" "'"
        "&lt;" "<"
        "&gt;" ">"
    } $s]
    return $s
}

proc bmkg_strip_tags {s} {
    regsub -all {<[^>]+>} $s " " s
    return [bmkg_trim [bmkg_htmldecode $s]]
}

proc bmkg_pick1 {re text {idx 1}} {
    if {[regexp -nocase -line -- $re $text -> m1]} {
        return [bmkg_strip_tags $m1]
    }
    return ""
}
proc bmkg_normalize {s} {
    set s [string tolower [bmkg_trim $s]]

    # replace literal sederhana
    set s [string map {
        "." " "
        "," " "
        "'" ""
        "\"" ""
        "-" " "
        "_" " "
    } $s]

    # phrase replace tanpa regex aneh
    set s [string map {
        "daerah khusus ibukota" "dki"
        "provinsi" ""
        "kabupaten administrasi" "kab"
        "kota administrasi" "kota"
        "kabupaten" "kab"
        "kecamatan" ""
        "kelurahan" ""
        "desa" ""
        "kepulauan" "kep"
    } $s]

    regsub -all {(^| )sel($| )} $s { selatan } s
    regsub -all {(^| )ut($| )}  $s { utara } s
    regsub -all {(^| )bar($| )} $s { barat } s
    regsub -all {(^| )tim($| )} $s { timur } s

    regsub -all {[^a-z0-9 ]} $s { } s
    regsub -all {[ ]+} $s { } s
    set s [string trim $s]

    array set alias {
        jakarta "dki jakarta"
        dki "dki jakarta"
        jakpus "jakarta pusat"
        jakut "jakarta utara"
        jakbar "jakarta barat"
        jaksel "jakarta selatan"
        jaktim "jakarta timur"
        "kota jakarta" "dki jakarta"
        "kota adm jakarta" "dki jakarta"
        "kota jakarta timur" "jakarta timur"
        "kota adm jakarta timur" "jakarta timur"
        "kota jakarta barat" "jakarta barat"
        "kota adm jakarta barat" "jakarta barat"
        "kota jakarta selatan" "jakarta selatan"
        "kota adm jakarta selatan" "jakarta selatan"
        "kota jakarta utara" "jakarta utara"
        "kota adm jakarta utara" "jakarta utara"
        "kota jakarta pusat" "jakarta pusat"
        "kota adm jakarta pusat" "jakarta pusat"
        solo "surakarta"
    }

    if {[info exists alias($s)]} {
        return $alias($s)
    }
    return $s
}

proc bmkg_escape_sql {s} {
    regsub -all {'} $s {''} s
    return $s
}

proc bmkg_format_adm4 {raw} {
    regsub -all {\D} $raw "" raw
    if {![regexp {^\d{10}$} $raw]} {
        return ""
    }
    return "[string range $raw 0 1].[string range $raw 2 3].[string range $raw 4 5].[string range $raw 6 9]"
}

proc bmkg_rowget {row key} {
    array set R $row
    if {[info exists R($key)]} {
        return $R($key)
    }
    return ""
}

proc bmkg_format_location {row} {
    set regency [bmkg_rowget $row regency]
    set province [bmkg_rowget $row province]

    regsub -nocase {^KAB\.\s*} $regency {Kab. } regency
    regsub -nocase {^KOTA ADM\.\s*} $regency {Kota } regency
    regsub -nocase {^KOTA\s*} $regency {Kota } regency
    regsub -nocase {^KAB\. ADM\.\s*} $regency {Kab. } regency

    return "$regency, $province"
}

# =========================
# DB EXEC
# =========================

proc bmkg_db_exec {sql} {
    global bmkg

    bmkg_log "psql_bin=$bmkg(psql)"
    bmkg_log "psql_host=$bmkg(db_host) db=$bmkg(db_name) user=$bmkg(db_user)"
    bmkg_log "sql_len=[string length $sql]"

    set sql_esc [string map {' '\\''} $sql]

    set cmd "PGPASSWORD='$bmkg(db_pass)' \"$bmkg(psql)\" -h \"$bmkg(db_host)\" -U \"$bmkg(db_user)\" -d \"$bmkg(db_name)\" -t -A -F '|' -c '$sql_esc'"

    bmkg_log "shell_cmd=jalan via sh -c"

    if {[catch {exec /bin/sh -c $cmd} out]} {
        return -code error $out
    }

    return [string trim $out]
}

# =========================
# SEARCH LOKASI
# =========================
proc bmkg_find_location {input} {
    set keyword [bmkg_normalize $input]
    if {$keyword eq ""} {
        return {}
    }

    set ksql [bmkg_escape_sql $keyword]
    set prefix "${ksql}%"
    set contains "%${ksql}%"

    bmkg_log "raw_query=$input | normalized=$keyword"

    set sql "
WITH q AS (
  SELECT '$ksql'::text AS keyword,
         '$prefix'::text AS prefix_keyword,
         '$contains'::text AS contains_keyword
),
regencies AS (
  SELECT
    'regency'::text AS matched_level,
    v.id AS adm4,
    TRIM(v.name) AS village,
    TRIM(d.name) AS district,
    TRIM(r.name) AS regency,
    TRIM(p.name) AS province,
    CASE
      WHEN lower(r.name) = (SELECT keyword FROM q) THEN 1000
      WHEN lower(replace(r.name, 'KAB. ', '')) = (SELECT keyword FROM q) THEN 1100
      WHEN lower(replace(r.name, 'KOTA ', '')) = (SELECT keyword FROM q) THEN 1100
      WHEN lower(replace(r.name, 'KOTA ADM. ', '')) = (SELECT keyword FROM q) THEN 1150
      WHEN lower(r.name) LIKE (SELECT prefix_keyword FROM q) THEN 800
      WHEN lower(replace(r.name, 'KAB. ', '')) LIKE (SELECT prefix_keyword FROM q) THEN 850
      WHEN lower(replace(r.name, 'KOTA ', '')) LIKE (SELECT prefix_keyword FROM q) THEN 850
      WHEN lower(replace(r.name, 'KOTA ADM. ', '')) LIKE (SELECT prefix_keyword FROM q) THEN 900
      WHEN lower(r.name) LIKE (SELECT contains_keyword FROM q) THEN 500
      WHEN lower(replace(r.name, 'KAB. ', '')) LIKE (SELECT contains_keyword FROM q) THEN 550
      WHEN lower(replace(r.name, 'KOTA ', '')) LIKE (SELECT contains_keyword FROM q) THEN 550
      WHEN lower(replace(r.name, 'KOTA ADM. ', '')) LIKE (SELECT contains_keyword FROM q) THEN 600
      ELSE 0
    END
    + CASE WHEN r.name ILIKE 'KOTA %' THEN 15 ELSE 0 END
    AS score
  FROM reg_regencies r
  JOIN reg_provinces p ON p.id = r.province_id
  JOIN LATERAL (
    SELECT dd.id, dd.name
    FROM reg_districts dd
    WHERE dd.regency_id = r.id
    ORDER BY dd.id ASC
    LIMIT 1
  ) d ON true
  JOIN LATERAL (
    SELECT vv.id, vv.name
    FROM reg_villages vv
    WHERE vv.district_id = d.id
    ORDER BY vv.id ASC
    LIMIT 1
  ) v ON true
  WHERE
    lower(r.name) LIKE (SELECT prefix_keyword FROM q)
    OR lower(replace(r.name, 'KAB. ', '')) LIKE (SELECT prefix_keyword FROM q)
    OR lower(replace(r.name, 'KOTA ', '')) LIKE (SELECT prefix_keyword FROM q)
    OR lower(replace(r.name, 'KOTA ADM. ', '')) LIKE (SELECT prefix_keyword FROM q)
    OR lower(r.name) LIKE (SELECT contains_keyword FROM q)
    OR lower(replace(r.name, 'KAB. ', '')) LIKE (SELECT contains_keyword FROM q)
    OR lower(replace(r.name, 'KOTA ', '')) LIKE (SELECT contains_keyword FROM q)
    OR lower(replace(r.name, 'KOTA ADM. ', '')) LIKE (SELECT contains_keyword FROM q)
),
provinces AS (
  SELECT
    'province'::text AS matched_level,
    v.id AS adm4,
    TRIM(v.name) AS village,
    TRIM(d.name) AS district,
    TRIM(r.name) AS regency,
    TRIM(p.name) AS province,
    CASE
      WHEN lower(p.name) = (SELECT keyword FROM q) THEN 900
      WHEN lower(p.name) LIKE (SELECT prefix_keyword FROM q) THEN 700
      WHEN lower(p.name) LIKE (SELECT contains_keyword FROM q) THEN 500
      ELSE 0
    END AS score
  FROM reg_provinces p
  JOIN LATERAL (
    SELECT rr.id, rr.name
    FROM reg_regencies rr
    WHERE rr.province_id = p.id
    ORDER BY
      CASE WHEN rr.name ILIKE 'KOTA %' OR rr.name ILIKE 'KOTA ADM. %' THEN 0 ELSE 1 END,
      rr.id ASC
    LIMIT 1
  ) r ON true
  JOIN LATERAL (
    SELECT dd.id, dd.name
    FROM reg_districts dd
    WHERE dd.regency_id = r.id
    ORDER BY dd.id ASC
    LIMIT 1
  ) d ON true
  JOIN LATERAL (
    SELECT vv.id, vv.name
    FROM reg_villages vv
    WHERE vv.district_id = d.id
    ORDER BY vv.id ASC
    LIMIT 1
  ) v ON true
  WHERE
    lower(p.name) LIKE (SELECT prefix_keyword FROM q)
    OR lower(p.name) LIKE (SELECT contains_keyword FROM q)
),
merged AS (
  SELECT * FROM regencies
  UNION ALL
  SELECT * FROM provinces
)
SELECT matched_level, adm4, village, district, regency, province, score
FROM merged
ORDER BY
  score DESC,
  CASE matched_level WHEN 'regency' THEN 1 ELSE 2 END,
  province,
  regency
LIMIT 10;
"

    if {[catch {bmkg_db_exec $sql} out]} {
        return -code error "query DB gagal: $out"
    }

    set rows {}
    foreach line [split $out "\n"] {
        set line [string trim $line]
        if {$line eq ""} continue

        set parts [split $line "|"]
        if {[llength $parts] < 7} continue

        lassign $parts matched_level adm4 village district regency province score

        lappend rows [list \
            matched_level $matched_level \
            adm4 $adm4 \
            village $village \
            district $district \
            regency $regency \
            province $province \
            score $score]
    }

    bmkg_log "rows_found=[llength $rows]"
    if {[llength $rows] > 0} {
        set best [lindex $rows 0]
        bmkg_log "best_match=[bmkg_format_location $best] | adm4_db=[bmkg_rowget $best adm4]"
    }

    return $rows
}

# =========================
# FETCH HTML BMKG
# =========================
proc bmkg_fetch_html {adm4Formatted} {
    global bmkg

    set url "https://www.bmkg.go.id/cuaca/prakiraan-cuaca/$adm4Formatted"

    set cmd "\"$bmkg(curl)\" -L --silent --show-error --max-time $bmkg(curl_timeout) \
-H \"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36\" \
-H \"Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8\" \
-H \"Accept-Language: id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7\" \
-H \"Cache-Control: no-cache\" \
-H \"Pragma: no-cache\" \
-H \"Referer: https://www.bmkg.go.id/\" \
\"$url\""

    bmkg_log "curl_url=$url"

    if {[catch {exec /bin/sh -c $cmd} out]} {
        return -code error $out
    }

    if {![string match -nocase "*Saat ini*" $out]} {
        return -code error "blok 'Saat Ini' tidak ditemukan"
    }

    return $out
}
# =========================
# PARSE HTML BMKG
# =========================
proc bmkg_parse_current {html} {
    array set R {
        pemutakhiran ""
        suhu ""
        cuaca ""
        lokasi ""
        kelembapan ""
        kecepatan_angin ""
        arah_angin ""
        jarak_pandang ""
    }

    set R(pemutakhiran) [bmkg_pick1 {Pemutakhiran:[[:space:]]*([^<]+)<} $html]
    set R(suhu) [bmkg_pick1 {font-bold\">?[[:space:]]*([0-9]+)[[:space:]]*°C} $html]
    set R(cuaca) [bmkg_pick1 {font-medium text-black-primary\">([^<]+)</p>[[:space:]]*<span[^>]*></span>[[:space:]]*<p[^>]*font-medium text-gray-primary\">} $html]
    set R(lokasi) [bmkg_pick1 {font-medium text-gray-primary\">[[:space:]]*di[[:space:]]*([^<]+)</p>} $html]
    set R(kelembapan) [bmkg_pick1 {Kelembapan:[[:space:]]*<span[^>]*>[[:space:]]*([^<]+)[[:space:]]*</span>} $html]
    set R(kecepatan_angin) [bmkg_pick1 {Kecepatan Angin:[[:space:]]*<span[^>]*>[[:space:]]*([^<]+)[[:space:]]*</span>} $html]
    set R(arah_angin) [bmkg_pick1 {Arah Angin dari:.*?text-black-primary font-bold\">([^<]+)</span>} $html]
    set R(jarak_pandang) [bmkg_pick1 {Jarak Pandang:.*?text-black-primary font-bold\">([^<]+)</span>} $html]

    bmkg_log "parsed_web suhu=$R(suhu) | cuaca=$R(cuaca) | lokasi=$R(lokasi) | hum=$R(kelembapan) | angin=$R(kecepatan_angin) | arah=$R(arah_angin) | jarak=$R(jarak_pandang)"

    return [array get R]
}
# =========================
# FORMAT OUTPUT
# =========================
proc bmkg_format_line {row dataArrName} {
    upvar 1 $dataArrName D

    set lokasi [bmkg_format_location $row]
    set cuaca "tidak diketahui"
    set suhu "-"
    set lembap "-"
    set angin "-"
    set arah ""
    set jarak ""

    if {$D(cuaca) ne ""} { set cuaca $D(cuaca) }
    if {$D(suhu) ne ""} { set suhu "$D(suhu)°C" }
    if {$D(kelembapan) ne ""} { set lembap $D(kelembapan) }
    if {$D(kecepatan_angin) ne ""} { set angin $D(kecepatan_angin) }
    if {$D(arah_angin) ne ""} { set arah ", arah $D(arah_angin)" }
    if {$D(jarak_pandang) ne ""} { set jarak ", jarak pandang $D(jarak_pandang)" }

    set line "\002$lokasi\002 - Saat ini $cuaca, suhu $suhu, kelembapan $lembap, angin $angin$arah$jarak"
    return [bmkg_trim $line]
}

# =========================
# HANDLER
# =========================
proc bmkg_handle {target text} {
    set query [bmkg_trim $text]

    if {$query eq ""} {
        putserv "PRIVMSG $target :Format: !cuaca <lokasi>  contoh: !cuaca jaktim"
        return
    }

    if {[catch {bmkg_find_location $query} rows err]} {
        putserv "PRIVMSG $target :Gagal query database: $err"
        return
    }

    if {[llength $rows] == 0} {
        putserv "PRIVMSG $target :Lokasi \"$query\" tidak ketemu di database wilayah Indonesia."
        return
    }

    set best [lindex $rows 0]
    set adm4_db [bmkg_rowget $best adm4]
    set adm4_bmkg [bmkg_format_adm4 $adm4_db]

    if {$adm4_bmkg eq ""} {
        putserv "PRIVMSG $target :adm4 tidak valid untuk lokasi \"$query\"."
        return
    }

    if {[catch {bmkg_fetch_html $adm4_bmkg} html err]} {
        putserv "PRIVMSG $target :Gagal ambil web BMKG: $err"
        return
    }

    array set D [bmkg_parse_current $html]

    putlog "CUACA DEBUG: query=$query | match=[bmkg_format_location $best] | district=[bmkg_rowget $best district] | village=[bmkg_rowget $best village] | adm4_db=$adm4_db | adm4_bmkg=$adm4_bmkg | suhu=$D(suhu) | cuaca=$D(cuaca) | lokasi=$D(lokasi) | hum=$D(kelembapan) | angin=$D(kecepatan_angin) | arah=$D(arah_angin) | jarak=$D(jarak_pandang)"

    set line [bmkg_format_line $best D]
    putserv "PRIVMSG $target :$line"
}

proc bmkg_pub {nick uhost hand chan text} {
    bmkg_log "masuk bmkg_pub | nick=$nick | chan=$chan | raw=$text | normalized=[bmkg_normalize $text]"
    bmkg_handle $chan $text
    return 0
}

proc bmkg_msg {nick uhost hand text} {
    bmkg_log "masuk bmkg_msg | nick=$nick | raw=$text | normalized=[bmkg_normalize $text]"
    bmkg_handle $nick $text
    return 0
}

putserv "PRIVMSG #fyp :BMKG TCL LOADED"
putlog "bmkg.tcl loaded"
