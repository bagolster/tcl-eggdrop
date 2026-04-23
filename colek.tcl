bind pub - !colek rollcall_cmd

proc rollcall_cmd {nick uhost hand chan text} {
    # Hapus baris set targetchan dan pengecekannya
    
    set maxlen 350
    set delay 2

    # Harus op di channel IRC, bukan cuma flag bot
    if {![isop $nick $chan]} {
        putserv "NOTICE $nick :Khusus op channel."
        return 0
    }

    # Pastikan bot ada di channel tersebut
    if {![botonchan $chan]} {
        putlog "ROLLCALL: bot tidak ada di $chan"
        return 0
    }

    # Kumpulkan semua nick di channel
    set allnicks [chanlist $chan]
    set botnick $::botnick
    set nicklist {}

    # Filter nick (kecualikan bot sendiri dan spasi kosong)
    foreach n $allnicks {
        if {[string equal -nocase $n $botnick]} { continue }
        if {[string trim $n] eq ""} { continue }
        lappend nicklist $n
    }

    # Kalau channel sepi
    if {[llength $nicklist] == 0} {
        putserv "PRIVMSG $chan :ga ada nick buat dicolek"
        return 0
    }

    # Urutkan nick sesuai abjad
    set nicklist [lsort -dictionary $nicklist]

    putserv "PRIVMSG $chan :Absen dimulai ......"

    set lines {}
    set current ""

    # Pisahkan nick ke beberapa baris agar tidak kena limit flood IRC
    foreach n $nicklist {
        if {$current eq ""} {
            set test $n
        } else {
            set test "$current, $n"
        }

        if {[string length $test] > $maxlen} {
            if {$current ne ""} {
                lappend lines $current
            }
            set current $n
        } else {
            set current $test
        }
    }

    if {$current ne ""} {
        lappend lines $current
    }

    # Kirim ke channel pakai delay (utimer)
    set sec 0
    foreach line $lines {
        utimer $sec [list putserv "PRIVMSG $chan :$line"]
        incr sec $delay
    }

    utimer $sec [list putserv "PRIVMSG $chan :Selesai. Total nick: [llength $nicklist]"]
    return 0
}

putlog "Script Colek All Channel Loaded!"
