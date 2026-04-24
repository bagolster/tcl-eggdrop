bind pub - !togel togel_cmd
bind msg - !togel togel_msg

namespace eval togel {
    variable url "https://tiga.bobamimin.com/json/fetch/index/data"
    variable timeout 20
}

proc togel_http_get {} {
    set url $::togel::url
    set timeout $::togel::timeout

    set cmd [list curl -k -L --silent --show-error --max-time $timeout $url]

    if {[catch {set data [exec {*}$cmd]} err]} {
        return -code error "gagal curl: $err"
    }

    if {$data eq ""} {
        return -code error "respon kosong"
    }

    return $data
}

proc togel_decode_number {raw} {
    set s $raw

    # decode escape dasar
    set s [string map [list \
        "\\u003C" "<" \
        "\\u003E" ">" \
        "\\u003c" "<" \
        "\\u003e" ">" \
        "\\/" "/" \
        "\\n" " " \
        "\\r" " " \
        "\\t" " " \
    ] $s]

    # buang tag HTML
    regsub -all {<[^>]+>} $s "" s

    # ambil digit saja
    regsub -all {[^0-9]} $s "" s

    if {$s eq ""} {
        return "-"
    }
    return $s
}

proc togel_get_market {json market today} {
    # PERBAIKAN 1: Pakai (?s).*? agar titik (.) bisa baca enter (\n) 
    # dan aman dari error kurung kurawal parser Tcl
    set blocks [regexp -all -inline {(?s)\{.*?\}} $json]
    
    foreach block $blocks {
        # Cocokkan nama market
        if {[regexp "\"name\"\\s*:\\s*\"$market\"" $block]} {
            set number ""
            set date ""
            
            # PERBAIKAN 2: Pakai kurung kurawal {} biar kurung siku [] 
            # tidak dieksekusi sebagai command Tcl yang bikin crash
            regexp {"number"\s*:\s*"([^"]+)"} $block -> number
            regexp {"date"\s*:\s*"([^"]+)"} $block -> date
            
            # Jika tanggal di JSON BEDA dengan hari ini, kembalikan "-"
            if {$date ne $today} {
                return "-"
            }
            
            # Jika tanggal sama, decode angkanya
            return [togel_decode_number $number]
        }
    }
    return "-"
}

proc togel_build_line {} {
    set json [togel_http_get]
    putlog "TOGEL RAW HEAD: [string range $json 0 400]"

    # Ambil tanggal hari ini (Format: DD-MM-YYYY)
    # Dicoba set timezone ke WIB agar pergantian hari akurat
    if {[catch {set today [clock format [clock seconds] -format "%d-%m-%Y" -timezone :Asia/Jakarta]}]} {
        # Fallback ke jam server kalau tcl tidak support timezone string
        set today [clock format [clock seconds] -format "%d-%m-%Y"]
    }

    set singapore [togel_get_market $json "SINGAPORE" $today]
    set hongkong  [togel_get_market $json "HONGKONG" $today]
    set sydney    [togel_get_market $json "SYDNEY" $today]
    set macau     [togel_get_market $json "4D Toto Macau" $today]

    putlog "TOGEL DEBUG: tanggal=$today singapore=$singapore hongkong=$hongkong sydney=$sydney macau=$macau"

    return "Info Tanggal $today | SINGAPORE = $singapore | HONGKONG = $hongkong | SYDNEY = $sydney | MACAU = $macau"
}

proc togel_cmd {nick uhost hand chan text} {
    if {[catch {set line [togel_build_line]} err]} {
        putserv "PRIVMSG $chan :Gagal ambil data togel: $err"
        return 0
    }
    putserv "PRIVMSG $chan :$line"
    return 0
}

proc togel_msg {nick uhost hand text} {
    if {[catch {set line [togel_build_line]} err]} {
        putserv "NOTICE $nick :Gagal ambil data togel: $err"
        return 0
    }
    putserv "NOTICE $nick :$line"
    return 0
}

putlog "togel.tcl loaded. Command: !togel"
