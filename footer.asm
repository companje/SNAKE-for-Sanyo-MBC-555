; Bepaal het aantal te lezen sectoren uit de daadwerkelijke stage-2-grootte.
%assign STAGE2_BYTES $-$$
%assign PROGRAM_BYTES BOOTLOADER_BYTES + STAGE2_BYTES
%warning PROGRAM_BYTES bytes (bootloader: BOOTLOADER_BYTES, app: STAGE2_BYTES)

APP_SECTORS equ (($-$$) + 511) / 512

%if ($-$$) > APP_SECTORS*512
  %error stage 2 is groter dan APP_SECTORS
%endif

%if APP_SECTORS > 359
  %error stage 2 past niet op een 180-KiB-disk met één bootsector
%endif

times APP_SECTORS*512-($-$$) db 0

; De bootsector staat al voor deze sectie op disk. Vul de rest van de image
; aan tot 40 tracks × 9 sectoren × 512 bytes (180 KiB).
times DISK_SIZE-BOOT_SECTOR_SIZE-($-$$) db 0
