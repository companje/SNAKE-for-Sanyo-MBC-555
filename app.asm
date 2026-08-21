%define SIZE_640x200

%include "header.asm"

FIELD_TOP    equ 8
FIELD_BOTTOM equ 199
FIELD_LEFT   equ 0
FIELD_RIGHT  equ 639

MENU_WIDTH  equ 400
MENU_HEIGHT equ 116
MENU_BYTES  equ MENU_WIDTH / 8
MENU_ROWS   equ MENU_HEIGHT / 4
MENU_PLANE  equ MENU_BYTES * MENU_HEIGHT
MENU_OFFSET equ (40 / 4) * ROW_BYTES + ((WIDTH - MENU_WIDTH) / 16) * 4
SCORE_X     equ WIDTH - 8 - (3 * 16)
SCORE_OFFSET equ (SCORE_X / 8) * 4
SPRITE_WIDTH  equ 32
SPRITE_HEIGHT equ 8
SPRITE_BYTES  equ SPRITE_WIDTH / 8
SPRITE_ROWS   equ SPRITE_HEIGHT / 4
SPRITE_PLANE  equ SPRITE_BYTES * SPRITE_HEIGHT
FOOD_SPRITE_TICKS equ 128      ; approximately two seconds at the current game-loop rate
SPRITE_NORMAL     equ 0
SPRITE_FOOD       equ 1
SPRITE_GAME_OVER  equ 2
PAUSE_WIDTH  equ 240
PAUSE_HEIGHT equ 40
PAUSE_BYTES  equ PAUSE_WIDTH / 8
PAUSE_ROWS   equ PAUSE_HEIGHT / 4
PAUSE_OFFSET equ (80 / 4) * ROW_BYTES + ((WIDTH - PAUSE_WIDTH) / 16) * 4
; The Sanyo layout requires a byte-aligned x position. This is x=304,
; four pixels to the right of the exact centre.
SPRITE_OFFSET equ ((WIDTH - SPRITE_WIDTH + 8) / 16) * 4

; One snake segment is 2x1 screen pixels: doubled horizontally, but one
; scanline high like the original game.
; The playfield has 318 horizontal 2x1 cells and 190 usable scanlines.
; The ring buffer is outside the loaded code at 2000:0000 and continues via
; 3000h. One free cell prevents the head and tail from coinciding in the ring.
SNAKE_CELLS       equ 318 * 190
SNAKE_MAX_LEN     equ SNAKE_CELLS - 1
SNAKE_POS_LOW_SEG equ 2000h
SNAKE_POS_HIGH_SEG equ 3000h
SNAKE_SEGMENT_CELLS equ 32768
SNAKE_INITIAL_LEN equ 14
SNAKE_START       equ ((100 / 4) * ROW_BYTES + (200 / 8) * 4) << 2
FOOD_INITIAL      equ (100 / 4) * ROW_BYTES + (304 / 8) * 4
GROWTH_PER_FOOD   equ 20
MOVE_DELAY        equ 4000
BOOST_EXTRA_STEPS equ 3
FOOD_SOUND_TONE equ 03eh
FOOD_SOUND_DURATION equ 10
CRASH_TONE_START equ 60h
CRASH_TONE_STEP  equ 07h
CRASH_TONE_STEPS equ 40
CRASH_TONE_DURATION equ 15

DIR_RIGHT equ 0
DIR_LEFT  equ 1
DIR_UP    equ 2
DIR_DOWN  equ 3

; The MBC-555 has a serial keyboard UART at these physical I/O ports.
KBD_DATA    equ 38h
KBD_CONTROL equ 3ah
KBD_RX_READY equ 02h
KEY_LEFT    equ 1ch
KEY_RIGHT   equ 1dh
KEY_UP      equ 1eh
KEY_DOWN    equ 1fh
KEY_ESCAPE  equ 1bh

CREDITS_LINE1_OFFSET equ (0 / 4) * ROW_BYTES
CREDITS_LINE2_OFFSET equ (8 / 4) * ROW_BYTES
CREDITS_LINE3_OFFSET equ (16 / 4) * ROW_BYTES

setup:
  push cs
  pop ds
  call init_menu_keyboard
  jmp menu_screen

menu_screen:
  call init_menu_keyboard
  call show_menu
menu_loop:
  call check_keys
  jz menu_loop
  cmp al,KEY_ESCAPE
  je credits_screen
  cmp al,' '
  je start_game
  and al,5fh
  cmp al,'Q'
  je credits_screen
  cmp al,'P'
  jne menu_loop
start_game:
  call init_game_keyboard
  call reset_game

game_loop:
  call read_keyboard
  call move_snake
  jc .crashed
 .boost:
  cmp byte [boost_moves],0
  je .keep_playing
  dec byte [boost_moves]
  call move_snake
  jnc .boost
.crashed:
  mov byte [top_sprite_state],SPRITE_GAME_OVER
  call draw_top_sprite
  call play_crash_sound
  jmp menu_screen
.keep_playing:
  call update_top_sprite
  mov cx,MOVE_DELAY
.delay:
  loop .delay
  jmp game_loop

; Pause on P. Redraw the game after the overlay is dismissed, because the
; pause picture overwrites the part of the playfield beneath it.
pause_game:
  call draw_pause
.wait_key:
  call check_keys
  jz .wait_key
  and al,5fh
  cmp al,'P'
  jne .wait_key
  call redraw_game
  ret

; Show the credits using the regular 8x8 ROM font and wait for one key.
credits_screen:
  call clear_screen_black
  mov si,credits_line1
  mov di,CREDITS_LINE1_OFFSET
  call draw_normal_text
  mov si,credits_line2
  mov di,CREDITS_LINE2_OFFSET
  call draw_normal_text
  mov si,credits_line3
  mov di,CREDITS_LINE3_OFFSET
  call draw_normal_text
.wait_key:
  call check_keys
  jz .wait_key
  jmp menu_screen

; The menu UART supplies ASCII for P and Space.
init_menu_keyboard:
  mov al,40h
  out KBD_CONTROL,al
  mov al,0bfh                ; 8 bit, even parity, 2 stopbits, klok /64
  out KBD_CONTROL,al
  mov al,14h                 ; receive enable + error reset
  out KBD_CONTROL,al
  ret

; The game UART configuration supplies the physical Sanyo cursor keys as
; ASCII control codes 1Ch..1Fh.
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

; Redraw the existing Sanyo menu as the start and game-over screen.
show_menu:
  call clear_screen
  mov si,menu_pic
  mov ax,BLUE
  mov es,ax
  call copy_menu_plane
  mov ax,GREEN
  mov es,ax
  call copy_menu_plane
  mov ax,RED
  mov es,ax
  call copy_menu_plane
  ret

; Convert a linear MENU_WIDTH×MENU_HEIGHT plane to Sanyo's four-scanline
; layout.
copy_menu_plane:
  mov di,MENU_OFFSET
  mov bp,MENU_ROWS
.row:
  mov bx,si
  mov cx,MENU_BYTES
.column:
  mov al,[bx]
  mov es:[di],al
  mov al,[bx + MENU_BYTES]
  mov es:[di + 1],al
  mov al,[bx + MENU_BYTES * 2]
  mov es:[di + 2],al
  mov al,[bx + MENU_BYTES * 3]
  mov es:[di + 3],al
  inc bx
  add di,4
  loop .column
  add di,ROW_BYTES - MENU_BYTES * 4
  add si,MENU_BYTES * 4
  dec bp
  jnz .row
  ret

; Draw the 240x40 pause image centred over the playfield. It is aligned to a
; four-scanline Sanyo row, just like the menu image.
draw_pause:
  push ax
  push si
  push es
  mov si,pause_pic
  mov ax,BLUE
  mov es,ax
  call copy_pause_plane
  mov ax,GREEN
  mov es,ax
  call copy_pause_plane
  mov ax,RED
  mov es,ax
  call copy_pause_plane
  pop es
  pop si
  pop ax
  ret

; Convert one linear PAUSE_WIDTHxPAUSE_HEIGHT colour plane to Sanyo VRAM.
copy_pause_plane:
  mov di,PAUSE_OFFSET
  mov bp,PAUSE_ROWS
.row:
  mov bx,si
  mov cx,PAUSE_BYTES
.column:
  mov al,[bx]
  mov es:[di],al
  mov al,[bx + PAUSE_BYTES]
  mov es:[di + 1],al
  mov al,[bx + PAUSE_BYTES * 2]
  mov es:[di + 2],al
  mov al,[bx + PAUSE_BYTES * 3]
  mov es:[di + 3],al
  inc bx
  add di,4
  loop .column
  add di,ROW_BYTES - PAUSE_BYTES * 4
  add si,PAUSE_BYTES * 4
  dec bp
  jnz .row
  ret

; Draw the active 32x8 sprite centred in the black margin above the playfield.
draw_top_sprite:
  push ax
  push bx
  push cx
  push dx
  push si
  push di
  push bp
  push es
  mov si,sprite1_pic
  cmp byte [top_sprite_state],SPRITE_GAME_OVER
  je .game_over
  cmp byte [top_sprite_state],SPRITE_FOOD
  jne .draw
  mov si,sprite2_pic
  jmp short .draw
.game_over:
  mov si,sprite3_pic
.draw:
  mov ax,BLUE
  mov es,ax
  call copy_sprite_plane
  mov ax,GREEN
  mov es,ax
  call copy_sprite_plane
  mov ax,RED
  mov es,ax
  call copy_sprite_plane
  pop es
  pop bp
  pop di
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; Convert a linear SPRITE_WIDTHxSPRITE_HEIGHT plane to Sanyo VRAM.
; On return, SI points to the next conventional colour plane.
copy_sprite_plane:
  mov di,SPRITE_OFFSET
  mov bp,SPRITE_ROWS
.row:
  mov bx,si
  mov cx,SPRITE_BYTES
.column:
  mov al,[bx]
  mov es:[di],al
  mov al,[bx + SPRITE_BYTES]
  mov es:[di + 1],al
  mov al,[bx + SPRITE_BYTES * 2]
  mov es:[di + 2],al
  mov al,[bx + SPRITE_BYTES * 3]
  mov es:[di + 3],al
  inc bx
  add di,4
  loop .column
  add di,ROW_BYTES - SPRITE_BYTES * 4
  add si,SPRITE_BYTES * 4
  dec bp
  jnz .row
  ret

; Show sprite 2 temporarily after food, then restore sprite 1.
update_top_sprite:
  cmp word [food_sprite_ticks],0
  je .done
  dec word [food_sprite_ticks]
  jnz .done
  mov byte [top_sprite_state],SPRITE_NORMAL
  call draw_top_sprite
.done:
  ret

; Read at most one typed key. Alongside WASD, the four physical cursor keys on
; the Sanyo numeric keypad work too: 8 up, 4 left, 5 down, and 6 right.
; An opposite direction is ignored.
read_keyboard:
  call check_keys
  jz .done
  cmp al,KEY_ESCAPE
  je credits_screen
  cmp al,KEY_UP
  je .up
  cmp al,KEY_DOWN
  je .down
  cmp al,KEY_LEFT
  je .left
  cmp al,KEY_RIGHT
  je .right
  and al,5fh                 ; convert ASCII to uppercase
  cmp al,'Q'
  je credits_screen
  cmp al,'P'
  je pause_game
  cmp al,'W'
  je .up
  cmp al,'8'
  je .up
  cmp al,'S'
  je .down
  cmp al,'5'
  je .down
  cmp al,'A'
  je .left
  cmp al,'4'
  je .left
  cmp al,'D'
  je .right
  cmp al,'6'
  jne .done
.right:
  cmp byte [snake_direction],DIR_LEFT
  je .done
  cmp byte [snake_direction],DIR_RIGHT
  je .boost
  mov byte [snake_direction],DIR_RIGHT
  ret
.left:
  cmp byte [snake_direction],DIR_RIGHT
  je .done
  cmp byte [snake_direction],DIR_LEFT
  je .boost
  mov byte [snake_direction],DIR_LEFT
  ret
.up:
  cmp byte [snake_direction],DIR_DOWN
  je .done
  cmp byte [snake_direction],DIR_UP
  je .boost
  mov byte [snake_direction],DIR_UP
  ret
.down:
  cmp byte [snake_direction],DIR_UP
  je .done
  cmp byte [snake_direction],DIR_DOWN
  je .boost
  mov byte [snake_direction],DIR_DOWN
.boost:
  mov byte [boost_moves],BOOST_EXTRA_STEPS
.done:
  ret

; Returns Z=0 when AL contains a newly received key code.
check_keys:
  in al,KBD_CONTROL
  mov ah,al
  and al,00001000b
  mov [cs:key.ctrl],al
  test ah,KBD_RX_READY
  jz .return
  in al,KBD_DATA
  mov [cs:key.code],al
  mov al,37h
  out KBD_CONTROL,al
  or al,1
  mov ax,[cs:key]
.return:
  ret

reset_game:
  call clear_screen
  call clear_top_margin
  call draw_playfield
  mov word [snake_head_index],0
  mov word [snake_length],SNAKE_INITIAL_LEN
  mov word [growth_remaining],0
  mov word [score],0
  mov word [food_sprite_ticks],0
  mov byte [top_sprite_state],SPRITE_NORMAL
  mov byte [snake_direction],DIR_RIGHT
  mov byte [boost_moves],0
  call draw_score

  xor di,di
  mov ax,SNAKE_START
  mov cx,SNAKE_INITIAL_LEN
.initial_cell:
  mov bx,di
  call write_snake_position
  push ax
  call draw_white_dot
  pop ax
  call step_left
  inc di
  loop .initial_cell
  mov word [food_offset],FOOD_INITIAL
  call draw_food
  ret

; Reconstruct the playfield after closing the pause overlay. Snake positions
; remain in the external ring buffer while the game is paused.
redraw_game:
  call clear_screen
  call clear_top_margin
  call draw_playfield
  call draw_score
  mov bx,[snake_head_index]
  mov cx,[snake_length]
.snake_segment:
  call read_snake_position
  call draw_white_dot
  inc bx
  cmp bx,SNAKE_CELLS
  jb .next_segment
  xor bx,bx
.next_segment:
  loop .snake_segment
  call draw_food
  ret

; CF=1 when the snake hits the border or its own body.
move_snake:
  mov bx,[snake_head_index]
  call read_snake_position
  cmp byte [snake_direction],DIR_RIGHT
  jne .not_right
  call step_right
  jmp short .new_head
.not_right:
  cmp byte [snake_direction],DIR_LEFT
  jne .not_left
  call step_left
  jmp short .new_head
.not_left:
  cmp byte [snake_direction],DIR_UP
  jne .down
  call step_up
  jmp short .new_head
.down:
  call step_down
.new_head:
  call is_outside_playfield
  jc .crashed
  mov byte [ate_food],0
  call is_food_at_position
  jc .eat_food

  ; The red plane is zero only on the blue background. Both border and body
  ; are white there, so they cause a collision.
  push ax
  call packed_to_vram
  mov bx,RED
  mov es,bx
  test byte [es:di],al
  pop ax
  jne .crashed
  jmp short .insert_head
.eat_food:
  call clear_food
  call play_food_sound
  inc word [score]
  cmp word [score],1000
  jb .score_in_range
  mov word [score],0
.score_in_range:
  mov word [food_sprite_ticks],FOOD_SPRITE_TICKS
  mov byte [top_sprite_state],SPRITE_FOOD
  call draw_score
  add word [growth_remaining],GROWTH_PER_FOOD
  mov byte [ate_food],1
.insert_head:
  mov bx,[snake_head_index]
  or bx,bx
  jnz .decrement_head
  mov bx,SNAKE_CELLS
.decrement_head:
  dec bx
  mov [snake_head_index],bx
  call write_snake_position
  call draw_white_dot

  cmp word [growth_remaining],0
  je .erase_tail
  cmp word [snake_length],SNAKE_MAX_LEN
  jae .growth_limit
  dec word [growth_remaining]
  inc word [snake_length]
  jmp short .after_tail

.growth_limit:
  ; Keep one free position in the ring buffer. At the limit, the tail keeps
  ; moving and remaining growth does not accumulate further.
  mov word [growth_remaining],0

.erase_tail:
  ; After insertion, the old tail is at head_index + length.
  mov bx,[snake_head_index]
  add bx,[snake_length]
  cmp bx,SNAKE_CELLS
  jb .tail_index_ok
  sub bx,SNAKE_CELLS
.tail_index_ok:
  call read_snake_position
  call clear_dot
.after_tail:
  cmp byte [ate_food],0
  je .ok
  call place_food
.ok:
  clc
  ret
.crashed:
  stc
  ret

; Choose an empty byte-aligned 8x4 position within the border using an LFSR.
; Invalid values are drawn again, keeping every position evenly distributed
; without a bias toward the left side.
place_food:
.try_again:
  mov ax,[random_seed]
  shr ax,1
  jnc .no_tap
  xor ax,0b400h
.no_tap:
  mov [random_seed],ax

  ; Column 1..78 (x=8..624), from the low seven bits.
  mov bx,ax
  and bx,007fh
  cmp bx,78
  jae .try_again
  inc bx
  shl bx,1
  shl bx,1
  mov di,bx

  ; Row 3..48 (y=12..192), from the high six bits.
  mov cl,8
  shr ax,cl
  and ax,003fh
  cmp ax,46
  jae .try_again
  add ax,3
  mov bx,ax
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl bx,1
  shl bx,1
  shl bx,1
  shl bx,1
  shl bx,1
  shl bx,1
  add di,ax
  add di,bx

  mov bx,RED
  mov es,bx
  cmp byte [es:di],0
  jne .try_again
  mov [food_offset],di
  call draw_food
  ret

clear_screen:
  mov ax,RED
  mov es,ax
  call clear_plane
  mov ax,GREEN
  mov es,ax
  call clear_plane
  mov ax,BLUE
  mov es,ax
  mov cx,PLANE_BYTES/2
  mov ax,-1
  xor di,di
  rep stosw
  ret

; Clear all three RGB planes for a fully black screen.
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

; Make the top eight scanlines black; they are outside the playfield.
clear_top_margin:
  mov ax,RED
  mov es,ax
  call clear_top_margin_plane
  mov ax,GREEN
  mov es,ax
  call clear_top_margin_plane
  mov ax,BLUE
  mov es,ax
  call clear_top_margin_plane
  ret

clear_top_margin_plane:
  xor ax,ax
  xor di,di
  mov cx,ROW_BYTES
  rep stosw
  ret

; Draw a blue/cyan checker pattern. Blue pixels are the existing background;
; only the green plane needs to be set for cyan pixels.
draw_playfield:
  mov al,FIELD_TOP
  call draw_dotted_hline
  mov al,FIELD_BOTTOM
  call draw_dotted_hline
  mov ax,GREEN
  mov es,ax
  call draw_dotted_vlines
  ret

; AL is a y coordinate. Blue, cyan, blue, cyan across a full scanline.
draw_dotted_hline:
  push ax
  push bx
  push cx
  push di
  push es
  xor ah,ah
  mov bx,ax
  and bx,3
  shr ax,1
  shr ax,1
  mov di,ax
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  add di,ax
  add di,bx
  mov ax,GREEN
  mov es,ax
  mov cx,COLS
  mov al,55h                 ; x=0 blue, x=1 cyan
.next_byte:
  mov es:[di],al
  add di,4
  loop .next_byte
  pop es
  pop di
  pop cx
  pop bx
  pop ax
  ret

; Vertical border: two pixels. Blue/cyan alternates on every scanline.
draw_dotted_vlines:
  mov di,((FIELD_TOP + 1) / 4) * ROW_BYTES + (FIELD_LEFT / 8) * 4 + ((FIELD_TOP + 1) & 3)
  mov al,40h                 ; left: blue, cyan
  mov ah,80h                 ; below: cyan, blue
  call draw_dotted_vline
  mov di,((FIELD_TOP + 1) / 4) * ROW_BYTES + (638 / 8) * 4 + ((FIELD_TOP + 1) & 3)
  mov al,01h                 ; right: blue, cyan
  mov ah,02h                 ; below: cyan, blue
  call draw_dotted_vline
  ret

; ES is the green plane, DI the first scanline, and AL/AH the alternating masks.
draw_dotted_vline:
  push bx
  push cx
  mov bl,(FIELD_TOP + 1) & 3
  mov cx,FIELD_BOTTOM - FIELD_TOP - 1
.next_pixel:
  or es:[di],al
  xchg al,ah
  inc bl
  cmp bl,4
  jb .same_block
  xor bl,bl
  add di,ROW_BYTES - 3
  loop .next_pixel
  jmp short .done
.same_block:
  inc di
  loop .next_pixel
.done:
  pop cx
  pop bx
  ret

; AL is a y coordinate. Write a full 640-pixel white line.
draw_white_hline:
  push ax
  push bx
  push cx
  push di
  push bp
  push es
  xor ah,ah
  mov bx,ax
  and bx,3
  shr ax,1
  shr ax,1
  mov di,ax
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1                    ; blok * 256
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1                    ; blok * 64
  add di,ax
  add di,bx
  mov bp,di
  mov ax,RED
  mov es,ax
  call draw_hline_in_plane
  mov ax,GREEN
  mov es,ax
  call draw_hline_in_plane
  mov ax,BLUE
  mov es,ax
  call draw_hline_in_plane
  pop es
  pop bp
  pop di
  pop cx
  pop bx
  pop ax
  ret

draw_hline_in_plane:
  mov di,bp
  mov cx,COLS
  mov al,0ffh
.next_byte:
  mov es:[di],al
  add di,4
  loop .next_byte
  ret

draw_white_vlines:
  mov di,(10 / 4) * ROW_BYTES + (FIELD_LEFT / 8) * 4 + (10 & 3)
  mov al,80h
  call draw_vline_in_plane
  mov di,(10 / 4) * ROW_BYTES + (FIELD_RIGHT / 8) * 4 + (10 & 3)
  mov al,01h
  call draw_vline_in_plane
  ret

draw_vline_in_plane:
  push bx
  push cx
  mov bl,10 & 3
  mov cx,FIELD_BOTTOM - FIELD_TOP - 1
.next_pixel:
  or es:[di],al
  inc bl
  cmp bl,4
  jb .same_block
  xor bl,bl
  add di,ROW_BYTES - 3
  loop .next_pixel
  jmp short .done
.same_block:
  inc di
  loop .next_pixel
.done:
  pop cx
  pop bx
  ret

; Positions contain the Sanyo VRAM offset in bits 2..15 and the two-pixel mask
; index in bits 0..1. This supports vertical movement by individual scanlines.
; BX is the ring buffer index. The buffer itself is outside code and stack in
; free RAM starting at 2000:0000; AX contains or receives the packed position.
read_snake_position:
  push bx
  push dx
  push es
  cmp bx,SNAKE_SEGMENT_CELLS
  jb .low_segment
  sub bx,SNAKE_SEGMENT_CELLS
  mov dx,SNAKE_POS_HIGH_SEG
  jmp short .read
.low_segment:
  mov dx,SNAKE_POS_LOW_SEG
.read:
  mov es,dx
  shl bx,1
  mov ax,es:[bx]
  pop es
  pop dx
  pop bx
  ret

write_snake_position:
  push bx
  push dx
  push es
  cmp bx,SNAKE_SEGMENT_CELLS
  jb .low_segment
  sub bx,SNAKE_SEGMENT_CELLS
  mov dx,SNAKE_POS_HIGH_SEG
  jmp short .write
.low_segment:
  mov dx,SNAKE_POS_LOW_SEG
.write:
  mov es,dx
  shl bx,1
  mov es:[bx],ax
  pop es
  pop dx
  pop bx
  ret

packed_to_vram:
  mov dx,ax
  mov bx,dx
  and bx,3
  shr dx,1
  shr dx,1
  mov di,dx
  mov al,[cs:dot_masks + bx]
  ret

; CF=1 if the 2x1 head would hit one of the four playfield borders. This check
; is separate from the visible blue/cyan border, whose blue pixels match the
; background colour.
is_outside_playfield:
  push ax
  push bx
  push cx
  push dx
  push si
  mov cx,ax
  and cx,3                    ; horizontale 2-pixelmaskindex
  call packed_to_vram
  mov ax,di
  xor dx,dx
  mov bx,ROW_BYTES
  div bx                       ; AX=vier-scanlineblok, DX=blokrest
  mov si,dx
  and si,3                     ; scanline 0..3 only, not the x position

  cmp ax,2                    ; y=0..7 is the black top margin
  jb .outside
  cmp ax,49
  ja .outside
  cmp ax,2
  jne .not_top_block
  cmp si,1                    ; only y=8 is on the top border
  jb .outside
.not_top_block:
  cmp ax,49
  jne .check_x
  cmp si,3                    ; y=199 is the bottom border
  jae .outside
.check_x:
  shr dx,1
  shr dx,1                    ; byte column 0..79
  or dx,dx
  jnz .not_left
  or cx,cx                    ; x=0/1 is the left border
  jz .outside
.not_left:
  cmp dx,COLS - 1
  jne .inside
  cmp cx,3                    ; x=638/639 is the right border
  je .outside
.inside:
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  clc
  ret
.outside:
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  stc
  ret

step_right:
  mov bx,ax
  and bx,3
  cmp bx,3
  jne .same_byte
  and ax,0fffch
  add ax,16                    ; next video-byte column
  ret
.same_byte:
  inc ax
  ret

step_left:
  mov bx,ax
  and bx,3
  or bx,bx
  jnz .same_byte
  and ax,0fffch
  sub ax,16                    ; previous video-byte column
  add ax,3
  ret
.same_byte:
  dec ax
  ret

step_up:
  mov bx,ax
  shr bx,1
  shr bx,1
  and bx,3
  or bx,bx
  jnz .same_block
  sub ax,1268                  ; offset -317 across the block boundary
  ret
.same_block:
  sub ax,4                     ; offset -1
  ret

step_down:
  mov bx,ax
  shr bx,1
  shr bx,1
  and bx,3
  cmp bx,3
  jne .same_block
  add ax,1268                  ; offset +317 across the block boundary
  ret
.same_block:
  add ax,4                     ; offset +1
  ret

; CF=1 if the 2x1 head hits a yellow pixel of the 8x4 food ball.
is_food_at_position:
  push ax
  call packed_to_vram
  mov bx,di
  sub bx,[food_offset]
  jb .not_food
  cmp bx,3
  ja .not_food
  mov ah,[food_masks + bx]
  test al,ah
  jz .not_food
  pop ax
  stc
  ret
.not_food:
  pop ax
  clc
  ret

; AX is a snake position. The white 2x1 pixel dot overwrites only its bits.
draw_white_dot:
  push ax
  push bx
  push cx
  push dx
  push si
  push di
  push es
  call packed_to_vram
  mov bx,RED
  mov es,bx
  or es:[di],al
  mov bx,GREEN
  mov es,bx
  or es:[di],al
  mov bx,BLUE
  mov es,bx
  or es:[di],al
  pop es
  pop di
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; AX is a snake position; restore only the blue background underneath it.
clear_dot:
  push ax
  push bx
  push cx
  push dx
  push si
  push di
  push es
  call packed_to_vram
  mov ah,al
  not ah
  mov bx,RED
  mov es,bx
  and es:[di],ah
  mov bx,GREEN
  mov es,bx
  and es:[di],ah
  mov bx,BLUE
  mov es,bx
  or es:[di],al
  pop es
  pop di
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; Yellow = red + green without blue. Only yellow bits are touched, leaving the
; four corner pixels of the 8x4 food ball blue.
draw_food:
  mov di,[food_offset]
  mov bx,RED
  mov es,bx
  call draw_food_in_red_or_green
  mov bx,GREEN
  mov es,bx
  call draw_food_in_red_or_green
  mov bx,BLUE
  mov es,bx
  and byte es:[di],0c3h
  and byte es:[di + 1],00h
  and byte es:[di + 2],00h
  and byte es:[di + 3],0c3h
  ret

draw_food_in_red_or_green:
  or byte es:[di],3ch
  or byte es:[di + 1],0ffh
  or byte es:[di + 2],0ffh
  or byte es:[di + 3],3ch
  ret

; Clear only the yellow pixels of the previous food ball and restore blue.
clear_food:
  mov di,[food_offset]
  mov bx,RED
  mov es,bx
  and byte es:[di],0c3h
  and byte es:[di + 1],00h
  and byte es:[di + 2],00h
  and byte es:[di + 3],0c3h
  mov bx,GREEN
  mov es,bx
  and byte es:[di],0c3h
  and byte es:[di + 1],00h
  and byte es:[di + 2],00h
  and byte es:[di + 3],0c3h
  mov bx,BLUE
  mov es,bx
  or byte es:[di],3ch
  or byte es:[di + 1],0ffh
  or byte es:[di + 2],0ffh
  or byte es:[di + 3],3ch
  ret

; The MBC-55x routes the USART break bit to the speaker. Preserve all game
; registers, because this routine runs exactly between calculating the head and
; inserting the new head into the snake.
play_food_sound:
  push ax
  push bx
  push cx
  push dx
  mov bx,FOOD_SOUND_TONE
  mov dx,FOOD_SOUND_DURATION
  call play
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; An increasing period means a descending tone: high to low.
play_crash_sound:
  push ax
  push bx
  push cx
  push dx
  push si
  mov bx,CRASH_TONE_START
  mov si,CRASH_TONE_STEPS
.next_note:
  mov dx,CRASH_TONE_DURATION
  call play
  add bx,CRASH_TONE_STEP
  dec si
  jnz .next_note
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; BX=note frequency, DX=duration.
play:
  mov cx,bx
  mov ax,35h
.toggle_break:
  xor al,8
  out KBD_CONTROL,al
.delay:
  dec ah
  jnz .continue
  dec dx
  jz .done
.continue:
  loop .delay
  mov cx,bx
  jmp .toggle_break
.done:
  ret

; Draw the score as three white ROM glyphs in the black top margin. Each source
; pixel is doubled horizontally with stretch_bits, making 8x8 into 16x8.
draw_score:
  push ax
  push bx
  push dx
  push di
  call clear_top_margin
  mov ax,[score]
  xor dx,dx
  mov bx,100
  div bx
  push dx
  add al,'0'
  mov di,SCORE_OFFSET          ; right-aligned, with an 8-pixel margin
  call draw_double_char
  pop ax
  xor dx,dx
  mov bx,10
  div bx
  push dx
  add al,'0'
  add di,8                    ; next double-width character
  call draw_double_char
  pop dx
  add dl,'0'
  mov al,dl
  add di,8                    ; next double-width character
  call draw_double_char
  call draw_top_sprite
  pop di
  pop dx
  pop bx
  pop ax
  ret

; DS:SI points to a null-terminated ASCII string; DI is the Sanyo VRAM start
; position. Characters use the unstretched 8x8 ROM font.
draw_normal_text:
  push ax
  push si
  push di
.next_char:
  lodsb
  or al,al
  jz .done
  call draw_normal_char
  add di,4                    ; next 8-pixel character
  jmp short .next_char
.done:
  pop di
  pop si
  pop ax
  ret

; AL=ASCII character, DI=Sanyo VRAM offset of the character on a four-line boundary.
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
  shl si,1                    ; acht bytes per 8x8-glyph
  add si,1000h                ; font op FE00:1000
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

; AL=ASCII character, DI=Sanyo VRAM offset of the first glyph byte at y=0.
draw_double_char:
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
  shl si,1                    ; acht bytes per 8x8-glyph
  add si,1000h                ; font op FE00:1000
  mov ax,ROM_SEG
  mov ds,ax
  mov bp,8
  xor dh,dh
.scanline:
  mov al,[si]
  call stretch_bits
  mov bx,RED
  mov es,bx
  mov es:[di],ah
  mov es:[di + 4],al
  mov bx,GREEN
  mov es,bx
  mov es:[di],ah
  mov es:[di + 4],al
  mov bx,BLUE
  mov es,bx
  mov es:[di],ah
  mov es:[di + 4],al
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

; AL=abcdefgh becomes AX=aabbccddeeffgghh.
stretch_bits:
  push cx
  push bx
  mov bl,al
  xor ax,ax
  mov cx,8
.bit:
  shl ax,1
  shl ax,1
  shl bl,1
  jnc .zero
  or ax,3
.zero:
  loop .bit
  pop bx
  pop cx
  ret

clear_plane:
  xor ax,ax
  xor di,di
  mov cx,PLANE_BYTES/2
  rep stosw
  ret

snake_direction:  db DIR_RIGHT
boost_moves:      db 0
ate_food:         db 0
snake_head_index: dw 0
snake_length:     dw SNAKE_INITIAL_LEN
growth_remaining: dw 0
score:            dw 0
food_sprite_ticks: dw 0
top_sprite_state: db SPRITE_NORMAL
food_offset:      dw FOOD_INITIAL
random_seed:      dw 0ace1h
dot_masks:        db 0c0h,30h,0ch,03h
food_masks:       db 3ch,0ffh,0ffh,3ch
key:
  .code db 0
  .ctrl db 0

credits_line1 db 'SNAKE.COM v1.00  by Rick Companje 17/12/1996',0
credits_line2 db 'Copyright (C) 1996  TMR Software Productions',0
credits_line3 db 'Rewritten with love in 2026 for the Sanyo MBC-550/555. Sanyo 4-ever!',0

; Drie conventionele scanline-planes in B, G, R-volgorde.
menu_pic:
  incbin "assets/sanyo/menu-ok-400-dithered-400x116.pic"

; Drie conventionele scanline-planes in B, G, R-volgorde.
sprite1_pic:
  incbin "assets/sanyo/sprite1-dithered-32x8.pic"

; Drie conventionele scanline-planes in B, G, R-volgorde.
sprite2_pic:
  incbin "assets/sanyo/sprite2-dithered-32x8.pic"

; Drie conventionele scanline-planes in B, G, R-volgorde.
sprite3_pic:
  incbin "assets/sanyo/sprite3-dithered-32x8.pic"

; Three conventional scanline planes in B, G, R order.
pause_pic:
  incbin "assets/sanyo/pause-dithered-240x40.pic"

%include "footer.asm"
