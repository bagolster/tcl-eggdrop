############################################################
# smartseen.tcl
# Smart seen for Eggdrop
############################################################

namespace eval seen {
    variable version "3.0"

    # ========= CONFIG =========
    variable trigger "!seen"
    variable dbfile "seen_smart.db"
    variable save_interval 300

    # {} = semua channel yang bot join
    variable track_channels {}

    # {} = command boleh di semua channel
    # contoh {#fyp}
    variable command_channels {}

    # 0 = abaikan bot
    variable track_bots 0

    # nick yang diabaikan
    variable ignore_nicks {ChanServ NickServ MemoServ OperServ BotServ}

    # command prefix yang tidak akan disimpan sebagai msg biasa
    variable ignore_command_prefixes {! . @ ?}

    # 0 = reply ke channel, 1 = notice ke user
    variable reply_notice 0

    # flood protection
    variable flood_seconds 5

    # ========= DATABASE =========
    variable nickdb
    array set nickdb {}

    variable hostdb
    array set hostdb {}

    variable aliasdb
    array set aliasdb {}

    variable lastcmd
    array set lastcmd {}
}

##############################
# Utility
##############################

proc seen::lc {s} {
    return [string tolower [string trim $s]]
}

proc seen::trimtext {s {max 220}} {
    set s [string trim $s]
    regsub -all {\s+} $s { } s
    if {[string length $s] > $max} {
        return "[string range $s 0 [expr {$max-4}]]..."
    }
    return $s
}

proc seen::is_tracked_channel {chan} {
    variable track_channels
    if {$chan eq ""} { return 1 }
    if {[llength $track_channels] == 0} { return 1 }

    set x [string tolower $chan]
    foreach c $track_channels {
        if {$x eq [string tolower $c]} {
            return 1
        }
    }
    return 0
}

proc seen::is_command_channel {chan} {
    variable command_channels
    if {[llength $command_channels] == 0} { return 1 }

    set x [string tolower $chan]
    foreach c $command_channels {
        if {$x eq [string tolower $c]} {
            return 1
        }
    }
    return 0
}

proc seen::is_ignored_nick {nick} {
    variable ignore_nicks
    variable track_bots

    set n [string tolower $nick]
    foreach x $ignore_nicks {
        if {$n eq [string tolower $x]} {
            return 1
        }
    }

    if {!$track_bots && [isbotnick $nick]} {
        return 1
    }

    return 0
}

proc seen::looks_like_command {text} {
    variable ignore_command_prefixes
    set t [string trimleft $text]
    if {$t eq ""} { return 0 }
    set ch [string index $t 0]
    foreach p $ignore_command_prefixes {
        if {$ch eq $p} {
            return 1
        }
    }
    return 0
}

proc seen::reply {chan nick text} {
    variable reply_notice
    if {$reply_notice} {
        puthelp "NOTICE $nick :$text"
    } else {
        puthelp "PRIVMSG $chan :$text"
    }
}

proc seen::fmt_ago {secs} {
    if {$secs < 0} { set secs 0 }

    set d [expr {$secs / 86400}]
    set secs [expr {$secs % 86400}]
    set h [expr {$secs / 3600}]
    set secs [expr {$secs % 3600}]
    set m [expr {$secs / 60}]
    set s [expr {$secs % 60}]

    set out {}
    if {$d > 0} { lappend out "${d}h" }
    if {$h > 0} { lappend out "${h}j" }
    if {$m > 0} { lappend out "${m}m" }
    if {$s > 0 || [llength $out] == 0} { lappend out "${s}d" }

    return [join $out " "]
}

proc seen::fmt_time {ts} {
    return [clock format $ts -format "%d-%m-%Y %H:%M:%S"]
}

proc seen::mkrec {nick uhost chan event text {extra ""}} {
    return [dict create \
        nick $nick \
        uhost [string trim $uhost] \
        chan $chan \
        event $event \
        text [seen::trimtext $text] \
        extra [seen::trimtext $extra] \
        ts [clock seconds]]
}

##############################
# Save / load
##############################

proc seen::save_db {} {
    variable dbfile
    variable nickdb
    variable hostdb
    variable aliasdb

    set f [open $dbfile w]
    fconfigure $f -encoding utf-8

    foreach k [array names nickdb] {
        puts $f [list set seen::nickdb($k) $nickdb($k)]
    }
    foreach k [array names hostdb] {
        puts $f [list set seen::hostdb($k) $hostdb($k)]
    }
    foreach k [array names aliasdb] {
        puts $f [list set seen::aliasdb($k) $aliasdb($k)]
    }

    close $f
}

proc seen::load_db {} {
    variable dbfile
    if {[file exists $dbfile]} {
        catch {source $dbfile}
    }
}

proc seen::periodic_save {} {
    variable save_interval
    catch {seen::save_db}
    utimer $save_interval seen::periodic_save
}

##############################
# Database core
##############################

proc seen::update_seen {nick uhost chan event text {extra ""}} {
    variable nickdb
    variable hostdb

    if {[seen::is_ignored_nick $nick]} { return }
    if {$chan ne "" && ![seen::is_tracked_channel $chan]} { return }

    set rec [seen::mkrec $nick $uhost $chan $event $text $extra]

    set nickkey [seen::lc $nick]
    set hostkey [seen::lc $uhost]

    set nickdb($nickkey) $rec
    if {$hostkey ne ""} {
        set hostdb($hostkey) $rec
    }
}

proc seen::resolve_alias {nick} {
    variable aliasdb

    set cur [seen::lc $nick]
    set guard 0

    while {[info exists aliasdb($cur)]} {
        set next $aliasdb($cur)
        if {$next eq "" || $next eq $cur} {
            break
        }
        set cur $next
        incr guard
        if {$guard > 20} {
            break
        }
    }

    return $cur
}

proc seen::find_latest_nickmatch {pattern} {
    variable nickdb

    set p [string tolower [string trim $pattern]]
    set best ""
    set bestts -1
    set hits 0

    foreach k [array names nickdb] {
        if {[string match $p $k]} {
            incr hits
            set rec $nickdb($k)
            set ts [dict get $rec ts]
            if {$ts > $bestts} {
                set bestts $ts
                set best $rec
            }
        }
    }

    return [list $hits $best]
}

proc seen::find_latest_hostmatch {pattern} {
    variable hostdb

    set p [string tolower [string trim $pattern]]
    set best ""
    set bestts -1
    set hits 0

    foreach k [array names hostdb] {
        if {[string match $p $k]} {
            incr hits
            set rec $hostdb($k)
            set ts [dict get $rec ts]
            if {$ts > $bestts} {
                set bestts $ts
                set best $rec
            }
        }
    }

    return [list $hits $best]
}

proc seen::find_latest_follow_by_host {uhost oldts} {
    variable hostdb

    set hk [seen::lc $uhost]
    if {$hk eq ""} { return "" }
    if {![info exists hostdb($hk)]} { return "" }

    set rec $hostdb($hk)
    set ts [dict get $rec ts]

    if {$ts > $oldts} {
        return $rec
    }
    return ""
}

proc seen::find_nickmatches_recent {pattern {limit 10}} {
    variable nickdb

    set p [string tolower [string trim $pattern]]
    set rows {}

    foreach k [array names nickdb] {
        if {[string match $p $k]} {
            set rec $nickdb($k)
            set ts [dict get $rec ts]
            lappend rows [list $ts $rec]
        }
    }

    set rows [lsort -decreasing -integer -index 0 $rows]

    set out {}
    set count 0
    foreach row $rows {
        lappend out [lindex $row 1]
        incr count
        if {$count >= $limit} {
            break
        }
    }

    return $out
}

proc seen::find_hostmatches_recent {pattern {limit 10}} {
    variable hostdb

    set p [string tolower [string trim $pattern]]
    set rows {}

    foreach k [array names hostdb] {
        if {[string match $p $k]} {
            set rec $hostdb($k)
            set ts [dict get $rec ts]
            lappend rows [list $ts $rec]
        }
    }

    set rows [lsort -decreasing -integer -index 0 $rows]

    set out {}
    set count 0
    foreach row $rows {
        lappend out [lindex $row 1]
        incr count
        if {$count >= $limit} {
            break
        }
    }

    return $out
}

proc seen::render_record {rec {displayNick ""}} {
    set nick  [dict get $rec nick]
    set uhost [dict get $rec uhost]
    set chan  [dict get $rec chan]
    set event [dict get $rec event]
    set text  [dict get $rec text]
    set extra [dict get $rec extra]
    set ts    [dict get $rec ts]

    if {$displayNick eq ""} {
        set who $nick
    } else {
        set who $displayNick
    }

    set ago  [seen::fmt_ago [expr {[clock seconds] - $ts}]]
    set when [seen::fmt_time $ts]

    switch -- $event {
        msg {
            return "$who terakhir terlihat $ago lalu di $chan, berkata: \"$text\" <$uhost> ($when)"
        }
        action {
            return "$who terakhir terlihat $ago lalu di $chan, action: * $text <$uhost> ($when)"
        }
        join {
            return "$who terakhir terlihat $ago lalu join ke $chan <$uhost> ($when)"
        }
        part {
            if {$text eq "" || $text eq "-"} {
                return "$who terakhir terlihat $ago lalu part dari $chan <$uhost> ($when)"
            } else {
                return "$who terakhir terlihat $ago lalu part dari $chan, alasan: \"$text\" <$uhost> ($when)"
            }
        }
        quit {
            set msg "$who terakhir terlihat $ago lalu quit IRC"
            if {$text ne "" && $text ne "-"} {
                append msg ", alasan: \"$text\""
            }
            append msg " <$uhost> ($when)"
            return $msg
        }
        nick {
            return "$who terakhir terlihat $ago lalu di $chan, ganti nick menjadi $text <$uhost> ($when)"
        }
        nick_from {
            return "$who terakhir terlihat $ago lalu di $chan, sebelumnya memakai nick $text <$uhost> ($when)"
        }
        kick {
            if {$text eq "" || $text eq "-"} {
                return "$who terakhir terlihat $ago lalu di-kick dari $chan oleh $extra <$uhost> ($when)"
            } else {
                return "$who terakhir terlihat $ago lalu di-kick dari $chan oleh $extra, alasan: \"$text\" <$uhost> ($when)"
            }
        }
        default {
            return "$who terakhir terlihat $ago lalu <$uhost> ($when)"
        }
    }
}

##############################
# Event handlers
##############################

proc seen::on_pubm {nick uhost hand chan text} {
    variable trigger

    if {![seen::is_tracked_channel $chan]} { return }
    if {[seen::is_ignored_nick $nick]} { return }

    if {[string match -nocase "${trigger}*" [string trimleft $text]]} {
        return
    }
    if {[seen::looks_like_command $text]} {
        return
    }

    if {[regexp "^\001ACTION (.*)\001$" $text -> act]} {
        seen::update_seen $nick $uhost $chan "action" $act
        return
    }

    seen::update_seen $nick $uhost $chan "msg" $text
}

proc seen::on_join {nick uhost hand chan} {
    if {![seen::is_tracked_channel $chan]} { return }
    if {[seen::is_ignored_nick $nick]} { return }
    seen::update_seen $nick $uhost $chan "join" ""
}

proc seen::on_part {nick uhost hand chan reason} {
    if {![seen::is_tracked_channel $chan]} { return }
    if {[seen::is_ignored_nick $nick]} { return }

    if {$reason eq ""} { set reason "-" }
    seen::update_seen $nick $uhost $chan "part" $reason
}

proc seen::on_sign {nick uhost hand args} {
    if {[seen::is_ignored_nick $nick]} { return }

    set chan ""
    set reason "-"

    if {[llength $args] == 1} {
        set reason [lindex $args 0]
    } elseif {[llength $args] >= 2} {
        set chan   [lindex $args 0]
        set reason [lindex $args 1]
    }

    if {$reason eq ""} { set reason "-" }
    seen::update_seen $nick $uhost $chan "quit" $reason
}

proc seen::on_nick {nick uhost hand chan newnick} {
    variable nickdb
    variable hostdb
    variable aliasdb

    if {![seen::is_tracked_channel $chan]} { return }
    if {[seen::is_ignored_nick $nick]} { return }

    set oldkey [seen::lc $nick]
    set newkey [seen::lc $newnick]
    set hostkey [seen::lc $uhost]

    seen::update_seen $nick $uhost $chan "nick" $newnick
    set aliasdb($oldkey) $newkey

    set newrec [seen::mkrec $newnick $uhost $chan "nick_from" $nick]
    set nickdb($newkey) $newrec
    if {$hostkey ne ""} {
        set hostdb($hostkey) $newrec
    }
}

proc seen::on_kick {nick uhost hand chan target reason} {
    variable nickdb

    if {![seen::is_tracked_channel $chan]} { return }
    if {[seen::is_ignored_nick $target]} { return }

    set targethost "unknown@unknown"
    set tk [seen::lc $target]
    if {[info exists nickdb($tk)]} {
        catch { set targethost [dict get $nickdb($tk) uhost] }
    }

    if {$reason eq ""} { set reason "-" }
    seen::update_seen $target $targethost $chan "kick" $reason $nick
}

##############################
# Command
##############################

proc seen::cmd_seen {nick uhost hand chan text} {
    variable nickdb
    variable lastcmd
    variable flood_seconds

    if {![seen::is_command_channel $chan]} {
        return 0
    }

    set q [string trim $text]
    if {$q eq ""} {
        seen::reply $chan $nick "Format: !seen <nick|hostmask>"
        return 1
    }

    set floodkey "[seen::lc $chan]|[seen::lc $nick]"
    set now [clock seconds]
    if {[info exists lastcmd($floodkey)] && (($now - $lastcmd($floodkey)) < $flood_seconds)} {
        seen::reply $chan $nick "Terlalu cepat. Coba lagi sebentar."
        return 1
    }
    set lastcmd($floodkey) $now

    set candidates {}

    set exactkey [seen::lc $q]
    set haswild [expr {[string first "*" $q] != -1 || [string first "?" $q] != -1}]
    set hasat   [expr {[string first "@" $q] != -1}]

    # 1) exact nick hanya kalau tidak pakai wildcard
    if {!$haswild} {
        if {[info exists nickdb($exactkey)]} {
            lappend candidates $nickdb($exactkey)
        }

        set resolved [seen::resolve_alias $q]
        if {$resolved ne $exactkey && [info exists nickdb($resolved)]} {
            lappend candidates $nickdb($resolved)
        }
    }

    # 2) wildcard nick hanya kalau user memang pakai wildcard
    if {$haswild} {
        set nickmatches [seen::find_nickmatches_recent $q 10]

        if {[llength $nickmatches] > 1} {
            set parts {}
            foreach rec $nickmatches {
                set nn [dict get $rec nick]
                set cc [dict get $rec chan]
                set ee [dict get $rec event]
                set tt [dict get $rec ts]
                set ago [seen::fmt_ago [expr {[clock seconds] - $tt}]]
                lappend parts "$nn ($cc, $ee, $ago lalu)"
            }
            seen::reply $chan $nick "Nick yang cocok dengan \"$q\" (maks 10 terbaru): [join $parts { | }]"
            return 1
        } elseif {[llength $nickmatches] == 1} {
            lappend candidates [lindex $nickmatches 0]
        }
    }

    # 3) host search
    if {$hasat || $haswild} {
        if {$haswild} {
            set hostmatches [seen::find_hostmatches_recent $q 10]

            if {[llength $hostmatches] > 1} {
                set parts {}
                foreach rec $hostmatches {
                    set nn [dict get $rec nick]
                    set cc [dict get $rec chan]
                    set ee [dict get $rec event]
                    set tt [dict get $rec ts]
                    set ago [seen::fmt_ago [expr {[clock seconds] - $tt}]]
                    set hh [dict get $rec uhost]
                    lappend parts "$nn ($cc, $ee, $ago lalu, <$hh>)"
                }
                seen::reply $chan $nick "Hostmask yang cocok dengan \"$q\" (maks 10 terbaru): [join $parts { | }]"
                return 1
            } elseif {[llength $hostmatches] == 1} {
                lappend candidates [lindex $hostmatches 0]
            }
        } else {
            lassign [seen::find_latest_hostmatch $q] hhits hrec
            if {$hhits > 0 && $hrec ne ""} {
                lappend candidates $hrec
            }
        }
    }

    if {[llength $candidates] == 0} {
        seen::reply $chan $nick "Saya belum pernah melihat \"$q\"."
        return 1
    }

    # ambil kandidat paling baru
    set best ""
    set bestts -1
    foreach rec $candidates {
        set ts [dict get $rec ts]
        if {$ts > $bestts} {
            set bestts $ts
            set best $rec
        }
    }

    set basets [dict get $best ts]
    set besthost [dict get $best uhost]
    set bestnick [dict get $best nick]
    set bestevent [dict get $best event]

    set base [seen::render_record $best $bestnick]

    set follow [seen::find_latest_follow_by_host $besthost $basets]
    if {$follow ne ""} {
        set fnick [dict get $follow nick]
        set fevent [dict get $follow event]
        set fchan [dict get $follow chan]

        if {[string tolower $fnick] ne [string tolower $bestnick]} {
            seen::reply $chan $nick "$base | Jejak lanjutan identitas yang sama: $fnick terakhir tercatat dengan event $fevent di $fchan. Detail: [seen::render_record $follow]"
        } else {
            seen::reply $chan $nick "$base | Ada update lebih baru dari identitas yang sama: [seen::render_record $follow]"
        }
        return 1
    }

    if {$bestevent eq "quit" || $bestevent eq "part" || $bestevent eq "nick"} {
        seen::reply $chan $nick "$base | Tidak ada jejak lanjutan dari identitas yang sama setelah itu."
        return 1
    }

    seen::reply $chan $nick $base
    return 1
}

##############################
# Init
##############################

proc seen::init {} {
    variable trigger
    variable version

    seen::load_db

    bind pubm - * seen::on_pubm
    bind join - * seen::on_join
    bind part - * seen::on_part
    bind sign - * seen::on_sign
    bind nick - * seen::on_nick
    bind kick - * seen::on_kick
    bind pub - $trigger seen::cmd_seen

    seen::periodic_save
    putlog "smartseen.tcl v$version loaded"
}

seen::init