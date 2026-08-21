%define SIZE_640x200

%include "header.asm"

KBD_DATA     equ 38h
KBD_CONTROL  equ 3ah
KBD_RX_READY equ 02h

LOG_OFFSET      equ (32 / 4) * ROW_BYTES
LOG_LINE_HEIGHT equ ROW_BYTES * 2
LOG_LINES       equ 20

setup:
  push cs
  pop ds
  mov al,5
  out 10h,al
  call clear_screen_black
  call draw_header
  call init_game_keyboard

.wait_key:
  call check_key
  jz .wait_key
  call log_key
  jmp .wait_key

; Use the same serial UART mode as the game. This is the mode that should
; report the four physical Sanyo cursor keys as their raw received bytes.
init_game_keyboard:
  xor al,al
  out KBD_CONTROL,al
  out KBD_CONTROL,al
  mov al,0ffh
  out KBD_CONTROL,al
  out KBD_CONTROL,al
  mov al,37h
  out KBD_CONTROL,al
  ret

; Return Z=0 with AL holding one received byte. key_status keeps the UART
; status that was read before the byte was acknowledged.
check_key:
  in al,KBD_CONTROL
  mov [key_status],al
  test al,KBD_RX_READY
  jz .none
  in al,KBD_DATA
  mov [key_code],al
  mov bl,al
  mov al,37h
  out KBD_CONTROL,al
  or bl,1
  mov al,[key_code]
.none:
  ret

; Print the received byte and its original UART status on the next line.
log_key:
  mov di,[log_offset]
  mov si,rx_label
  call write_text
  mov al,[key_code]
  call write_hex
  mov si,status_label
  call write_text
  mov al,[key_status]
  call write_hex

  add word [log_offset],LOG_LINE_HEIGHT
  inc byte [log_line_count]
  cmp byte [log_line_count],LOG_LINES
  jb .done
  call clear_screen_black
  call draw_header
  mov word [log_offset],LOG_OFFSET
  mov byte [log_line_count],0
.done:
  ret

draw_header:
  xor di,di
  mov si,title_line1
  call write_text
  mov di,ROW_BYTES * 2
  mov si,title_line2
  call write_text
  ret

; DS:SI is a zero-terminated string. DI advances by one 8-pixel glyph.
write_text:
.next:
  lodsb
  or al,al
  jz .done
  call put_char
  jmp .next
.done:
  ret

put_char:
  call draw_normal_char
  add di,4
  ret

; Print AL as two uppercase hexadecimal digits.
write_hex:
  push bx
  mov bl,al
  shr al,1
  shr al,1
  shr al,1
  shr al,1
  call hex_digit
  call put_char
  mov al,bl
  and al,0fh
  call hex_digit
  call put_char
  pop bx
  ret

hex_digit:
  cmp al,10
  jb .number
  add al,'A' - 10
  ret
.number:
  add al,'0'
  ret

; Draw one white 8x8 ROM glyph at DI, which must point at a four-scanline
; Sanyo VRAM boundary or one of its four scanline offsets.
draw_normal_char:
  push ax
  push bx
  push cx
  push dx
  push di
  push si
  push bp
  push es
  push ds
  xor ah,ah
  mov si,ax
  shl si,1
  shl si,1
  shl si,1
  add si,1000h
  mov ax,ROM_SEG
  mov ds,ax
  mov bp,8
  xor dh,dh
.scanline:
  mov al,[si]
  mov bx,RED
  mov es,bx
  mov es:[di],al
  mov bx,GREEN
  mov es,bx
  mov es:[di],al
  mov bx,BLUE
  mov es,bx
  mov es:[di],al
  inc si
  inc di
  inc dh
  cmp dh,4
  jb .next_scanline
  xor dh,dh
  add di,ROW_BYTES - 4
.next_scanline:
  dec bp
  jnz .scanline
  pop ds
  pop es
  pop bp
  pop si
  pop di
  pop dx
  pop cx
  pop bx
  pop ax
  ret

clear_screen_black:
  mov ax,RED
  mov es,ax
  call clear_plane
  mov ax,GREEN
  mov es,ax
  call clear_plane
  mov ax,BLUE
  mov es,ax
  call clear_plane
  ret

clear_plane:
  xor ax,ax
  xor di,di
  mov cx,PLANE_BYTES / 2
  rep stosw
  ret

log_offset:     dw LOG_OFFSET
log_line_count: db 0
key_code:       db 0
key_status:     db 0
title_line1:    db 'SANYO MBC-55X KEYBOARD DEBUG',0
title_line2:    db 'PRESS KEYS - RAW UART BYTES:',0
rx_label:       db 'RX: ',0
status_label:   db '  STATUS: ',0

%include "footer.asm"
