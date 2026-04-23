# Load package JSON bawaan tcllib
package require json

# Bind perintah public, misal: !whois google.com
bind pub - !whois pub:cek_whois

# Masukkan token API kamu di sini
set whois_api_token "at_h8aqA5YjjnQhzJnidqwtktDaO4KFG"

proc pub:cek_whois {nick uhost hand chan text} {
    global whois_api_token
    
    set domain [lindex [split $text] 0]
    
    if {$domain eq ""} {
        putserv "PRIVMSG $chan :Cara pakai: !whois <namadomain.com>"
        return 0
    }

    # --- 1. FILTER: BLOKIR IP ADDRESS ---
    # Mengecek apakah input hanya berisi angka dan titik (IPv4) atau mengandung titik dua (IPv6)
    if {[regexp {^[0-9\.]+$} $domain] || [string first ":" $domain] != -1} {
        putserv "PRIVMSG $chan :\002\00304\[ERROR\]\003\002 Maaf, command ini khusus untuk \002Nama Domain\002, bukan IP Address."
        return 0
    }

    # URL API
    set api_url "https://www.whoisxmlapi.com/whoisserver/WhoisService?domainName=${domain}&outputFormat=JSON"
    
    # Eksekusi curl
    if {[catch {exec curl -s --location $api_url --header "Authorization: Bearer $whois_api_token"} response]} {
        putserv "PRIVMSG $chan :\002\00304\[ERROR\]\003\002 Gagal menghubungi server API."
        return 0
    }

    # Parsing respons JSON
    if {[catch {set parsed [::json::json2dict $response]} parse_err]} {
        putserv "PRIVMSG $chan :\002\00304\[ERROR\]\003\002 Gagal memproses data JSON."
        return 0
    }

    # Cek apakah blok "WhoisRecord" ada
    if {[dict exists $parsed WhoisRecord]} {
        set record [dict get $parsed WhoisRecord]
        
        # Setup variabel default
        set registrar "Tidak diketahui"
        set created "Tidak diketahui"
        set expires "Tidak diketahui"
        set nameservers "Tidak ada data NS"

        # Ambil Registrar Name
        if {[dict exists $record registrarName]} {
            set registrar [dict get $record registrarName]
        }

        # Fokus parsing di dalam registryData
        if {[dict exists $record registryData]} {
            set regData [dict get $record registryData]
            
            # Ambil Tanggal
            if {[dict exists $regData createdDate]} { set created [dict get $regData createdDate] }
            if {[dict exists $regData expiresDate]} { set expires [dict get $regData expiresDate] }
            
            if {$registrar eq "Tidak diketahui" && [dict exists $regData registrarName]} {
                set registrar [dict get $regData registrarName]
            }

            # Ambil NameServers
            if {[dict exists $regData nameServers hostNames]} {
                set ns_list [dict get $regData nameServers hostNames]
                set nameservers [join $ns_list ", "]
            } elseif {[dict exists $regData nameServers rawText]} {
                set ns_raw [string trim [dict get $regData nameServers rawText]]
                set nameservers [string map {"\n" ", "} $ns_raw]
            }
        }

        # --- 2. PERCANTIK TAMPILAN: WARNA & FORMAT TANGGAL ---
        # Hapus huruf T dan Z pada format tanggal dari API
        set created_clean [string map {"T" " " "Z" ""} $created]
        set expires_clean [string map {"T" " " "Z" ""} $expires]

        # Kode Warna mIRC yang digunakan (Aman untuk background putih/hitam mIRC):
        # \00302 = Biru Gelap
        # \00304 = Merah
        # \00303 = Hijau Gelap
        # \00314 = Abu-abu (untuk garis pemisah | )
        
        putserv "PRIVMSG $chan :\002\00302\[WHOIS\]\003\002 \002$domain\002 \00314|\003 Registrar: \002$registrar\002"
        putserv "PRIVMSG $chan :\002\00304\[DATE\]\003\002 Created: \002$created_clean\002 \00314|\003 Expires: \002$expires_clean\002"
        putserv "PRIVMSG $chan :\002\00303\[NS\]\003\002 \002$nameservers\002"

    } else {
         putserv "PRIVMSG $chan :\002\00304\[ERROR\]\003\002 Data WHOIS tidak ditemukan untuk \002$domain\002."
    }
    return 1
}

putlog "Script Whois API (v2 - Colored & IP Block) Loaded"
