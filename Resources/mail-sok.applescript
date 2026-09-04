-- Soker mejl till eller fran en adress i Mail.
--
-- Anropas som: osascript mail-sok.applescript <adress> <max antal per lada>
--
-- Gransen galler per lada, inte totalt. Annars skulle inkorgen fylla hela
-- kvoten och skickade mejl aldrig komma med. Anroparen sorterar pa datum.
-- Svarar med en rad per mejl, falten atskilda av ASCII 31 (unit separator),
-- eftersom amnesrader garna innehaller bade tabbar och rortecken.
--
-- AppleScript-identifierare maste vara ASCII, darav stavningen har.
-- Kommentarer far daremot innehalla å ä ö.
--
-- Inkorgen filtreras på avsändare, skickat på mottagare. Att filtrera på
-- avsändare även i skickat vore meningslöst: där är avsändaren alltid jag.

on run argv
	set adress to item 1 of argv
	set grans to (item 2 of argv) as integer
	set faltdelare to (ASCII character 31)
	set ut to ""

	tell application "Mail"
		repeat with konto in accounts
			set kontonamn to name of konto

			-- Inkorgen: mejl från personen
			set raknare to 0
			try
				set traffar to (every message of mailbox "INBOX" of konto whose sender contains adress)
				repeat with m in traffar
					if raknare >= grans then exit repeat
					set raknare to raknare + 1
					set ut to ut & my rad(m, kontonamn, "INBOX", "fran", faltdelare)
				end repeat
			end try

			-- Skickat: mejl till personen.
			-- "sent mailbox of konto" finns inte i Mails ordlista, och lådan
			-- heter olika beroende på konto och språk, så namnen provas i tur.
			set raknare to 0
			repeat with kandidat in {"Sent Messages", "Sent", "Skickat", "Skickade objekt"}
				try
					set skickat to mailbox (kandidat as string) of konto
					set traffar to (every message of skickat whose (address of every to recipient) contains adress)
					repeat with m in traffar
						if raknare >= grans then exit repeat
						set raknare to raknare + 1
						set ut to ut & my rad(m, kontonamn, kandidat as string, "till", faltdelare)
					end repeat
					exit repeat
				end try
			end repeat
		end repeat
	end tell
	return ut
end run

on rad(m, kontonamn, ladnamn, riktning, faltdelare)
	tell application "Mail"
		-- Datumet lämnas två gånger: som text för visning, och som
		-- "ÅÅÅÅ-MM-DD HH:MM:SS" i lokal tid för appen. Textformen följer
		-- datorns språk, och appen förstod bara den engelska: på en svensk
		-- dator fick inget mejl något datum alls.
		set dd to missing value
		try
			set dd to date received of m
		on error
			try
				set dd to date sent of m
			end try
		end try
		set d to ""
		set iso to ""
		if dd is not missing value then
			set d to dd as string
			set iso to my isodatum(dd)
		end if
		try
			set a to sender of m
		on error
			set a to ""
		end try
		try
			set s to subject of m
		on error
			set s to "(utan amne)"
		end try
		-- Brödtexten är ofta det som betyder något; ämnesraden säger sällan
		-- vad som faktiskt stod. Kapas för att svaret inte ska bli ohanterligt.
		try
			set b to content of m
			if (count of b) > 4000 then set b to (text 1 thru 4000 of b)
			-- Radbrytningar skulle bryta radformatet; de blir mellanslag.
			set gamla to AppleScript's text item delimiters
			set AppleScript's text item delimiters to {linefeed, return, tab}
			set delar to text items of b
			set AppleScript's text item delimiters to " "
			set b to delar as string
			set AppleScript's text item delimiters to gamla
		on error
			set b to ""
		end try
		try
			set mid to message id of m
		on error
			set mid to ""
		end try
		return d & faltdelare & a & faltdelare & s & faltdelare & mid & faltdelare & kontonamn & faltdelare & ladnamn & faltdelare & riktning & faltdelare & b & faltdelare & iso & linefeed
	end tell
end rad

on tvasiffror(n)
	if n < 10 then return "0" & n
	return "" & n
end tvasiffror

on isodatum(dd)
	set y to year of dd
	set mo to (month of dd) as integer
	set da to day of dd
	set t to time of dd
	set h to t div 3600
	set mi to (t mod 3600) div 60
	set se to t mod 60
	return (y as string) & "-" & my tvasiffror(mo) & "-" & my tvasiffror(da) & " " & my tvasiffror(h) & ":" & my tvasiffror(mi) & ":" & my tvasiffror(se)
end isodatum
