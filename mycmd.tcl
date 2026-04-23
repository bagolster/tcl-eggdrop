# mycmds.tcl - Perintah Dasar Manajemen Bot (Versi Original + Save + Rehash)

# Bind command untuk Public (di channel) - Flag 'n' (owner)
bind pub n .join pub_join
bind pub n .part pub_part
bind pub n .rehash pub_rehash

# Bind command untuk Private Message (PM) - Flag 'n' (owner)
bind msg n .join msg_join
bind msg n .part msg_part
bind msg n .rehash msg_rehash

# ==========================================
# Fungsi .join (Public)
# ==========================================
proc pub_join {nick uhost hand chan text} {
    if {$text == ""} { 
        putserv "PRIVMSG $chan :Gunakan: .join <#channel>" 
        return 0 
    }
    channel add [lindex $text 0]
    save
    putserv "PRIVMSG $chan :Siap bos, meluncur ke [lindex $text 0] dan udah di-save!"
}

# ==========================================
# Fungsi .part (Public)
# ==========================================
proc pub_part {nick uhost hand chan text} {
    if {$text == ""} {
        putserv "PRIVMSG $chan :Keluar dari $chan..."
        channel remove $chan
        save
    } else {
        putserv "PRIVMSG $chan :Keluar dari [lindex $text 0]..."
        channel remove [lindex $text 0]
        save
    }
}

# ==========================================
# Fungsi .rehash (Public)
# ==========================================
proc pub_rehash {nick uhost hand chan text} {
    putserv "PRIVMSG $chan :Melaksanakan rehash... bentar ya bos."
    rehash
    putserv "PRIVMSG $chan :Rehash selesai! Script udah fresh lagi."
}

# ==========================================
# Fungsi .join via PM
# ==========================================
proc msg_join {nick uhost hand text} {
    if {$text == ""} { 
        putserv "PRIVMSG $nick :Gunakan: .join <#channel>" 
        return 0 
    }
    channel add [lindex $text 0]
    save
    putserv "PRIVMSG $nick :Siap, saya sudah masuk ke [lindex $text 0] dan datanya udah di-save!"
}

# ==========================================
# Fungsi .part via PM
# ==========================================
proc msg_part {nick uhost hand text} {
    if {$text == ""} {
        putserv "PRIVMSG $nick :Gunakan: .part <#channel>"
    } else {
        putserv "PRIVMSG $nick :Siap, saya keluar dari [lindex $text 0]"
        channel remove [lindex $text 0]
        save
    }
}

# ==========================================
# Fungsi .rehash via PM
# ==========================================
proc msg_rehash {nick uhost hand text} {
    putserv "PRIVMSG $nick :Melaksanakan rehash via PM..."
    rehash
    putserv "PRIVMSG $nick :Rehash selesai bos!"
}

putlog "Loaded: mycmds.tcl (Original Version + Save + Rehash) by Owner"