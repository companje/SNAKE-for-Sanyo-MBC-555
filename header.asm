cpu 8086

ROM_READ equ 01e78h
ROM_SEG  equ 0fe00h
LOAD_SEG equ 1000h

BOOT_SECTOR_SIZE equ 512
DISK_SIZE        equ 180 * 1024

RED   equ 0f000h
GREEN equ 0800h
BLUE  equ 0f400h

; Selecteer de schermgeometrie. Bij geen keuze is 576×200 de standaard.
%ifdef SIZE_640x200
  %ifdef SIZE_576x200
    %error SIZE_640x200 en SIZE_576x200 kunnen niet tegelijk actief zijn
  %endif
%else
  %ifndef SIZE_576x200
    %define SIZE_576x200
  %endif
%endif

%ifdef SIZE_640x200
  WIDTH equ 640
%else
  WIDTH equ 576
%endif

HEIGHT      equ 200
ROW         equ HEIGHT / 4
COLS        equ WIDTH / 8
ROW_BYTES   equ COLS * 4
PLANE_BYTES equ ROW_BYTES * ROW

CRTC_INDEX_PORT equ 30h
CRTC_DATA_PORT  equ 32h

; ---------------------------------------------------------------------------
; Sector 1: draait op 0038:0000 en blijft daar resident.
; Laadt stage 2 vanaf sector 2 naar 1000:0000.
; ---------------------------------------------------------------------------
section .boot start=0 vstart=0 align=1

boot:
  cli
  cld
  mov ax,es
  test ah,ah
  jne sector_done

  mov cx,APP_SECTORS
  mov bl,2
  xor bp,bp                  ; huidige track
  mov ax,LOAD_SEG
  mov es,ax
  jmp short read_sector

sector_done:
  loop more

  ; Eenmalige stackinitialisatie na de laatste sector.
  mov ax,LOAD_SEG
  mov ss,ax
  mov sp,0fffeh

%ifdef SIZE_640x200
  ; De ROM heeft de 72-kolomsmodus al gezet. Voor 640×200 verschillen alleen
  ; HD6845-registers 1, 2 en 3.
  mov al,1
  out CRTC_INDEX_PORT,al
  mov al,80
  out CRTC_DATA_PORT,al
  mov al,2
  out CRTC_INDEX_PORT,al
  mov al,89
  out CRTC_DATA_PORT,al
  mov al,3
  out CRTC_INDEX_PORT,al
  mov al,72
  out CRTC_DATA_PORT,al
%endif

  jmp LOAD_SEG:0

more:
  inc bl
  cmp bl,10                  ; sectoren zijn genummerd 1..9
  jb advance_load_address

  mov bl,1
  inc bp                     ; volgende track
  mov ax,bp
  out 0eh,al                 ; nieuw tracknummer voor de FDC
  mov al,18h
  out 08h,al                 ; seek track, load head
  xor al,al
  out 1ch,al                 ; drive 0, side 0
  aam                        ; korte wachttijd

.head_moving:
  in al,08h
  test al,1
  jnz .head_moving

advance_load_address:
  mov ax,es
  add ax,20h                 ; volgende 512 bytes in RAM
  mov es,ax

read_sector:
  mov al,bl
  out 0ch,al
  jmp ROM_SEG:ROM_READ

%assign BOOTLOADER_BYTES $-$$

; ---------------------------------------------------------------------------
; Sector 2 en verder: staan op disk direct na de bootsector, maar worden door
; de loader naar 1000:0000 geladen. De entrypoint springt naar `setup` in
; app.asm.
; ---------------------------------------------------------------------------
section .stage start=512 vstart=0 align=1

  jmp setup
