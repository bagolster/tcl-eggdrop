# ==========================================
# detiknews.tcl - RSS Auto Poster with Queue (Auto All Channels)
# ==========================================

# 1. Amankan memori data biar nggak amnesia pas rehash
if {![info exists detik(queue)]} { set detik(queue) {} }
if {![info exists detik(seen)]} { set detik(seen) {} }

# 2. Copot bind lama (kalau ada) biar bersih, lalu pasang bind baru
catch {unbind cron - "* * * * *" detiknews}
bind cron - "* * * * *" detiknews

proc detik_queue_has {guid} {
    global detik
    foreach item $detik(queue) {
        if {[lindex $item 0] eq $guid} {
            return 1
        }
    }
    return 0
}

proc detiknews {min hour day month weekday} {
    global detik

    # Tarik data dari RSS
    catch {exec curl --connect-timeout 5 -L -s https://news.detik.com/rss} data
    if {$data eq ""} {
        return
    }

    # Ambil per blok <item> ... </item>
    set items [regexp -all -inline {(?s)<item>(.*?)</item>} $data]
    if {[llength $items] == 0} {
        return
    }

    set count 0

    foreach {fullMatch itemData} $items {
        set guid ""
        set update ""
        set title ""

        regexp {(?s)<guid[^>]*>(.*?)</guid>} $itemData -> guid
        regexp {(?s)<pubDate>(.*?)</pubDate>} $itemData -> update
        regexp {(?s)<title>\s*(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?\s*</title>} $itemData -> title

        set guid [string trim $guid]
        set update [string trim $update]
        set title [string trim $title]

        if {$guid eq "" || $title eq ""} {
            continue
        }

        if {[lsearch -exact $detik(seen) $guid] == -1 && ![detik_queue_has $guid]} {
            lappend detik(queue) [list $guid $update $title]
        }

        incr count
        if {$count >= 5} {
            break
        }
    }

    # Kirim cuma 1 item per menit
    if {[llength $detik(queue)] > 0} {
        set item [lindex $detik(queue) 0]
        set detik(queue) [lrange $detik(queue) 1 end]

        set guid   [lindex $item 0]
        set update [lindex $item 1]
        set title  [lindex $item 2]

        regsub { \+0700$} $update "" update

        set update_indo [string map {
            "Mon," "Senin ," "Tue," "Selasa ," "Wed," "Rabu ," "Thu," "Kamis ," "Fri," "Jumat ," "Sat," "Sabtu ," "Sun," "Minggu ,"
            "Jan" "Januari" "Feb" "Februari" "Mar" "Maret" "Apr" "April" "May" "Mei" "Jun" "Juni" "Jul" "Juli" "Aug" "Agustus" "Sep" "September" "Oct" "Oktober" "Nov" "November" "Dec" "Desember"
        } $update]

        # FIX: Otomatis deteksi & kirim ke semua channel tempat bot join
        foreach c [channels] {
            putquick "PRIVMSG $c :\002detik.com\002 \0034-\003 $title \0034(\003$update_indo\0034)\003"
        }

        lappend detik(seen) $guid

        if {[llength $detik(seen)] > 50} {
            set detik(seen) [lrange $detik(seen) end-49 end]
        }
    }
}

putlog "Loaded: detiknews.tcl (Auto Broadcast All Channels) by Owner"