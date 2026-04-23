# netflix_release.tcl
# Command: !netflix
# Eggdrop TCL - pakai curl saja, tanpa jq

namespace eval netflixrel {
    variable base_url "https://about.netflix.com/api/data/releases?language=en&country=ID&page=%d"
    variable max_items 10
    variable timeout 25
}

bind pub - !netflix netflixrel::cmd_netflix

proc netflixrel::fetch_page {page} {
    variable base_url
    variable timeout

    set url [format $base_url $page]
    set cmd [list curl -L -s --connect-timeout $timeout --max-time $timeout \
        -H "accept: application/json, text/plain, */*" \
        -H "user-agent: Mozilla/5.0" \
        $url]

    if {[catch {eval exec $cmd} res]} {
        putlog "NETFLIX: curl error page $page: $res"
        return ""
    }

    return $res
}

proc netflixrel::extract_total_pages {json} {
    if {[regexp {"totalPages"[[:space:]]*:[[:space:]]*([0-9]+)} $json -> pages]} {
        return $pages
    }
    return 1
}

proc netflixrel::extract_data_block {json} {
    # ambil isi array "data": [ ... ]
    if {[regexp -indices {"data"[[:space:]]*:[[:space:]]*\[(.*)\][[:space:]]*\}} $json -> range]} {
        set start [lindex $range 0]
        set end   [lindex $range 1]
        return [string range $json $start $end]
    }

    # fallback lebih longgar
    if {[regexp {"data"[[:space:]]*:[[:space:]]*\[(.*)\]} $json -> block]} {
        return $block
    }
    return ""
}

proc netflixrel::extract_objects_from_data {data_block} {
    set out {}
    set level 0
    set start -1
    set in_string 0
    set esc 0
    set len [string length $data_block]

    for {set i 0} {$i < $len} {incr i} {
        set ch [string index $data_block $i]

        if {$in_string} {
            if {$esc} {
                set esc 0
            } elseif {$ch eq "\\"} {
                set esc 1
            } elseif {$ch eq "\""} {
                set in_string 0
            }
            continue
        }

        if {$ch eq "\""} {
            set in_string 1
            continue
        }

        if {$ch eq "\{"} {
            if {$level == 0} {
                set start $i
            }
            incr level
        } elseif {$ch eq "\}"} {
            incr level -1
            if {$level == 0 && $start >= 0} {
                lappend out [string range $data_block $start $i]
                set start -1
            }
        }
    }

    return $out
}

proc netflixrel::json_get_string {obj key} {
    set pattern [format {"%s"[[:space:]]*:[[:space:]]*"([^"\\]*(\\.[^"\\]*)*)"} $key]

    if {[regexp -nocase -- $pattern $obj -> val]} {
        set val [string map {
            "\\/" "/"
            "\\\"" "\""
            "\\n" " "
            "\\r" " "
            "\\t" " "
        } $val]
        return [string trim $val]
    }
    return ""
}

proc netflixrel::json_get_number {obj key} {
    set pattern [format {"%s"[[:space:]]*:[[:space:]]*([0-9]+)} $key]

    if {[regexp -nocase -- $pattern $obj -> val]} {
        return $val
    }
    return ""
}

proc netflixrel::parse_page_items {json} {
    set results {}
    regsub -all {\r|\n|\t} $json " " json

    set data_block [extract_data_block $json]
    if {$data_block eq ""} {
        return $results
    }

    foreach obj [extract_objects_from_data $data_block] {
        set title1 [json_get_string $obj "title1"]
        set title2 [json_get_string $obj "title2"]
        set startMs [json_get_number $obj "startTime"]

        if {$title1 eq ""} { continue }
        if {$startMs eq ""} { continue }

        set startSec [expr {$startMs / 1000}]

        if {$title2 ne "" && [string tolower $title2] ne [string tolower $title1]} {
            set fulltitle "$title1: $title2"
        } else {
            set fulltitle $title1
        }

        lappend results [dict create \
            title1 $title1 \
            title2 $title2 \
            title $fulltitle \
            start_ms $startMs \
            start_sec $startSec]
    }

    return $results
}

proc netflixrel::dedup_items {items} {
    array set seen {}
    set out {}

    foreach item $items {
        set key "[string tolower [dict get $item title]]|[dict get $item start_ms]"
        if {![info exists seen($key)]} {
            set seen($key) 1
            lappend out $item
        }
    }
    return $out
}

proc netflixrel::sort_desc {a b} {
    set ta [dict get $a start_sec]
    set tb [dict get $b start_sec]

    if {$ta > $tb} { return -1 }
    if {$ta < $tb} { return 1 }
    return 0
}

proc netflixrel::fmt_date {epoch} {
    return [clock format $epoch -format "%d %b %Y"]
}

proc netflixrel::collect_all_items {} {
    set all {}
    set json1 [fetch_page 1]
    if {$json1 eq ""} {
        return {}
    }

    set totalPages [extract_total_pages $json1]
    putlog "NETFLIX: totalPages=$totalPages"

    foreach item [parse_page_items $json1] {
        lappend all $item
    }

    for {set p 2} {$p <= $totalPages} {incr p} {
        set json [fetch_page $p]
        if {$json eq ""} {
            putlog "NETFLIX: skip page $p karena kosong/error"
            continue
        }
        foreach item [parse_page_items $json] {
            lappend all $item
        }
    }

    return [dedup_items $all]
}

proc netflixrel::cmd_netflix {nick host hand chan text} {
    variable max_items

    set now [clock seconds]
    set today [clock format $now -format "%d %b %Y"]

    set items [collect_all_items]
    if {[llength $items] == 0} {
        puthelp "PRIVMSG $chan :Netflix: gagal ambil atau parse data."
        return
    }

    set filtered {}
    foreach item $items {
        set ts [dict get $item start_sec]
        if {$ts <= $now} {
            lappend filtered $item
        }
    }

    if {[llength $filtered] == 0} {
        puthelp "PRIVMSG $chan :Netflix: tidak ada rilisan sampai $today."
        return
    }

    set filtered [lsort -command netflixrel::sort_desc $filtered]
    set picked [lrange $filtered 0 [expr {$max_items - 1}]]

    puthelp "PRIVMSG $chan :Netflix ID terbaru sampai $today:"
    set no 1
    foreach item $picked {
        set title [dict get $item title]
        set rdate [fmt_date [dict get $item start_sec]]

        if {[string length $title] > 220} {
            set title "[string range $title 0 216]..."
        }

        puthelp "PRIVMSG $chan :\00300,04 NETFLIX \017 $title - $rdate"
        incr no
    }
}