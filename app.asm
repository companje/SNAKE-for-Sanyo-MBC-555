%define SIZE_640x200

%include "header.asm"

MENU_BYTES  equ 336 / 8
MENU_ROWS   equ 116 / 4
MENU_PLANE  equ MENU_BYTES * 116
MENU_OFFSET equ (40 / 4) * ROW_BYTES + ((640 - 336) / 16) * 4

setup:
  push cs
  pop ds

  ; Clear red and green; fill blue for the background.
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

  ; menu.pic contains three conventional scanline planes: B, G, R.
  mov si,menu_pic
  mov ax,BLUE
  mov es,ax
  call copy_plane
  mov ax,GREEN
  mov es,ax
  call copy_plane
  mov ax,RED
  mov es,ax
  call copy_plane

  jmp draw

; Copy one 336x116 linear plane, aligned to Sanyo four-scanline VRAM.
copy_plane:
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

clear_plane:
  xor ax,ax
  xor di,di
  mov cx,PLANE_BYTES/2
  rep stosw
  ret

draw:
  jmp draw

menu_pic:
  incbin "assets/sanyo/menu-ok-336x116.pic"

%include "footer.asm"
