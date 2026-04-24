# xxi.tcl - Now Playing XXI via curl, tanpa json/jq
# butuh: curl

bind pub - !xxi pub_xxi
bind msg - !xxi msg_xxi

proc xxi_json_unescape {s} {
    regsub -all {\\\"} $s {"} s
    regsub -all {\\\\} $s {\\} s
    regsub -all {\\\/} $s {/} s
    regsub -all {\\n} $s { } s
    regsub -all {\\r} $s { } s
    regsub -all {\\t} $s { } s
    regsub -all {\s+} $s { } s
    return [string trim $s]
}

proc xxi_extract_titles {rawData} {
    set out {}

    regsub -all {\r} $rawData {} rawData
    regsub -all {\n} $rawData {} rawData

    # cari semua posisi "title":"..."
    set pos 0
    set hits {}

    while {[regexp -indices -start $pos {"title":"((?:[^"\\]|\\.)*)"} $rawData m titleIdx]} {
        lassign $m a b
        lassign $titleIdx ta tb

        set fullMatch [string range $rawData $a $b]
        set title     [string range $rawData $ta $tb]

        lappend hits [list $a $b $title]
        set pos [expr {$b + 1}]
    }

    set total [llength $hits]
    for {set i 0} {$i < $total} {incr i} {
        set cur [lindex $hits $i]
        set start [lindex $cur 0]
        set title [lindex $cur 2]

        if {$i < ($total - 1)} {
            set next [lindex $hits [expr {$i + 1}]]
            set end [expr {[lindex $next 0] - 1}]
        } else {
            set end [expr {[string length $rawData] - 1}]
        }

        set chunk [string range $rawData $start $end]

        # cek apakah di chunk item ini ada is_now_playing true
        if {[regexp -nocase {"is_now_playing"[[:space:]]*:[[:space:]]*true} $chunk]} {
            set title [xxi_json_unescape $title]
            if {$title ne "" && [lsearch -exact $out $title] == -1} {
                lappend out $title
            }
        }
    }

    return $out
}

proc get_xxi_data {target} {
    set url "https://m.21cineplex.com/api/movies?type=now-playing&city_id=72"

    putserv "PRIVMSG $target :Sabar bos, kuli bot lagi OTW XXI bentar ngintip jadwal tayang..."

    if {[catch {
        set rawData [exec curl -sL --max-time 15 --compressed \
            -H "Accept: application/json" \
            -H "User-Agent: Mozilla/5.0" \
            $url]
    } err]} {
        putserv "PRIVMSG $target :Gagal nyambung ke API 21Cineplex ($err)."
        return
    }

    if {[string trim $rawData] eq ""} {
        putserv "PRIVMSG $target :API XXI ngasih respon kosong."
        return
    }

    set titles [xxi_extract_titles $rawData]

    if {[llength $titles] == 0} {
        putserv "PRIVMSG $target :Saat ini tidak ada film yang berstatus Now Playing."
        return
    }

    set numbered {}
    set n 1
    foreach title $titles {
        lappend numbered "\00308,12 ${n} \017 \[$title\]"
        incr n
    }

    # 4 judul per baris
    set lineData {}
    foreach item $numbered {
        lappend lineData $item
        if {[llength $lineData] == 4} {
            putserv "PRIVMSG $target :[join $lineData " - "]"
            set lineData {}
        }
    }

    if {[llength $lineData] > 0} {
        putserv "PRIVMSG $target :[join $lineData " - "]"
    }
}

proc pub_xxi {nick uhost hand chan text} {
    get_xxi_data $chan
}

proc msg_xxi {nick uhost hand text} {
    get_xxi_data $nick
}

putlog "Loaded: xxi.tcl (Now Playing XXI via curl, no json, check is_now_playing true)"