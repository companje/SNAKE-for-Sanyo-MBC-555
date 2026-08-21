; Derive the number of sectors to read from the actual stage-2 size.
%assign STAGE2_BYTES $-$$
%assign PROGRAM_BYTES BOOTLOADER_BYTES + STAGE2_BYTES
%warning PROGRAM_BYTES bytes (bootloader: BOOTLOADER_BYTES, app: STAGE2_BYTES)

APP_SECTORS equ (($-$$) + 511) / 512

%if ($-$$) > APP_SECTORS*512
  %error stage 2 is groter dan APP_SECTORS
%endif

%if APP_SECTORS > 359
  %error stage 2 does not fit on a 180-KiB disk with one boot sector
%endif

times APP_SECTORS*512-($-$$) db 0

; The boot sector already precedes this section on disk. Pad the rest of the
; image to 40 tracks × 9 sectors × 512 bytes (180 KiB).
times DISK_SIZE-BOOT_SECTOR_SIZE-($-$$) db 0
