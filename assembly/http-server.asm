; primitive http 1.0 server with 2 GET endpoints
;   /health - returns a OK server up response
;   / - returns a premade index.html file
; blocking by default, single conn handler at a time

; USAGE
; terminal 1
; nasm -felf64 http-server.asm && ld http-server.o -o server && ./server
;
; terminal 2
; curl -i localhost:5555/          
; curl -i localhost:5555/health     # 200 + "Server is running"

; CONSTANTS

; syscalls
SYS_read        equ 0
SYS_write       equ 1
SYS_open        equ 2 
SYS_close       equ 3 
SYS_socket      equ 41
SYS_accept      equ 43
SYS_sendto      equ 44
SYS_bind        equ 49
SYS_listen      equ 50
SYS_setsockopt  equ 54
SYS_exit        equ 60 

; flags
AF_INET      equ 2  ; IpV4 addr
SOCK_STREAM  equ 1  ; TCP (reliable byte stream)
SOL_SOCKET   equ 1  ; socket level opts
SO_REUSEADDR equ 2  ; allow reuse when restarting
MSG_NOSIGNAL equ 0x4000 ; prevent send() raising SIGPIPE

; alias
BUF_SIZE equ 4096 ; 4KiB buf alias
CR equ 13         ; /r
LF equ 10         ; /n
PORT equ 0xB315   ; 5555 default port (newtork byte order)
LOCALHOST equ 0x0100007F  ; 127.0.0.1

; globals
section .bss
  buf resb BUF_SIZE ; reserve 4 KiB buffer

; read-only data
section .rodata

; 16 byte C equivalent struct socketaddr_in
addr:
  dw AF_INET  ; 2 byte
  dw PORT     ; 2 byte
  dd LOCALHOST; 4 byte
  dq 0        ; 8 bytes, 0 init padding

addr_len equ $ - addr ; 16 byte

one: dd 1  ; 4 byte setsockopt option value (passed by pointer)

; RESPONSES

; body embedded at assemble time
index_body:
    incbin "html/index.html"
index_body_len equ $ - index_body

; header split around the Content-Length number
index_hdr_start:
    db "HTTP/1.1 200 OK", CR, LF
    db "Content-Type: text/html; charset=utf-8", CR, LF
    db "Content-Length: "
index_hdr_start_len equ $ - index_hdr_start

index_hdr_end:
    db CR, LF
    db "Connection: close", CR, LF
    db CR, LF
index_hdr_end_len equ $ - index_hdr_end

; 404, only support GET / /health
not_found_response:
    db "HTTP/1.1 404 Not Found", CR, LF
    db "Content-Type: text/plain", CR, LF
    db "Content-Length: 9", CR, LF
    db "Connection: close", CR, LF
    db CR, LF
    db "Not Found"
not_found_response_len equ $ - not_found_response

; 200, GET /health
health_response:
    db "HTTP/1.1 200 Ok", CR, LF
    db "Content-Type: text/plain", CR, LF
    db "Content-Length: 17", CR, LF
    db "Connection: close", CR, LF
    db CR, LF
    db "Server is running"
health_response_len equ $ - health_response

; Endpoints 
index_url       db "GET / "
index_url_len   equ $ - index_url

health_url      db "GET /health "
health_url_len  equ $ - health_url

; CLI messages
start_msg db "Server starting on port 5555...", LF
start_msg_len equ $ - start_msg

listen_msg db "Server listening...", LF
listen_msg_len equ $ - listen_msg

close_msg db "Connection closed", LF
close_msg_len equ $ - close_msg

error_msg db "Error occurred!", LF
error_msg_len equ $ - error_msg

; reopen .bss to get index_response buf 
section .bss
  index_response resb 256 + index_body_len   ; headers + body

; code 
section .text
  global _start

; FROM wc.asm
; utoa = unsigned int to decimal formatted value
; utoa(rax = value, rdi = dest) -> rdi = one past the last digit written
; Clobbers: rax, rcx, rdx, rsi, r8
utoa:
  mov r8, rsp   ; r8 = end of scratch area below rsp 
  mov rsi, r8   ; rsi = write cursor moving downwards 
  mov ecx, 10
.digit:
  xor edx, edx  ; div divides rdx:rax, clear high half 
  div rcx       ; rax = value / 10, rdx = value % 10 
  add dl, '0'   ; remainder as ASCII digit 
  dec rsi
  mov [rsi], dl ; store digits right to left 
  test rax, rax
  jnz .digit    ; do while: 0 emits '0'

  mov rcx, r8   ; 
  sub rcx, rsi  ; rcx = digit amount 
  rep movsb     ; copy rcx bytes from [rsi] to [rdi] and advance both
  ret

; build_index_response() -> rax = total response length in bytes
; Fills index_response with: status line, headers, blank line, body.
; Clobbers: rax, rcx, rdx, rsi, rdi, r8
build_index_response:
  lea  rdi, [rel index_response]    ; rdi = append cursor, needed to calculate index.html dynamic len

  lea  rsi, [rel index_hdr_start]   ; "HTTP/1.1 200 OK ... Content-Length: "
  mov  ecx, index_hdr_start_len
  rep  movsb  ; repeatedly copy byte from RSI -> RDI advancing both pointers

  mov  eax, index_body_len          ; the number itself as Content-Length
  call utoa                         ; appends ASCII digits, advances rdi

  lea  rsi, [rel index_hdr_end]     ; "\r\nConnection: close\r\n\r\n"
  mov  ecx, index_hdr_end_len
  rep  movsb

  lea  rsi, [rel index_body]        ; the HTML content
  mov  ecx, index_body_len
  rep  movsb

  mov  rax, rdi                     ; length = cursor - start
  lea  rcx, [rel index_response]
  sub  rax, rcx
  ret


; prefix_match(rsi = data, rdx = data_len, rdi = prefix, rcx = prefix_len)
;   -> eax = 1 if data starts with prefix, else 0
; Clobbers: rax, rcx, rsi, rdi
;
; repe = repreat whle equal ZF=1
; cmpse = compare the byte at RSI with byte ad rdi and advance addr pointer
; repe cmpse = compare bytes between two mem reigons until they differ or counter is 0
prefix_match:
    xor  eax, eax   ; set 0
    cmp  rdx, rcx   ; data len and prefix_len cmp
    jb   .done      ; data shorter than prefix: can't match
    repe cmpsb      ; compare [rsi] vs [rdi] while equal, up to rcx bytes
    jne  .done      ; stopped on a mismatch
    mov  eax, 1     ; all prefix_len bytes matched
.done:
    ret

; Register use:
;   rbx = listening socket fd
;   r12 = current client fd
;   r13 = errno on failure
_start:
  ; load index.html for GET /
  call build_index_response
  mov r14, rax  ; r14 = index response len

  ; socket(AF_INET, SOCK_STREAM, 0)
  mov eax, SYS_socket
  mov edi, AF_INET
  mov esi, SOCK_STREAM
  xor edx, edx  ; 0
  syscall

  test rax, rax
  js  .error    ; js = jump if sign = jump if return num 1 (err)
  mov rbx, rax  ; rbx = listener_fd

  ; setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &one, 4)
  mov eax, SYS_setsockopt
  mov rdi, rbx  ; l_fd
  mov esi, SOL_SOCKET
  mov edx, SO_REUSEADDR
  lea r10, [rel one]    ; 4th syscall arg in r10, not rcx
  mov r8d, 4            ; size &one, 4 bytes
  syscall

  test rax, rax
  js  .error

  ; bind(listen_fd, &addr, addr_len)
  mov eax, SYS_bind
  mov rdi, rbx  ; l_fd
  lea rsi, [rel addr]
  mov edx, addr_len
  syscall

  test rax, rax
  js  .error

  ; listen(listen_fd, 16)
  mov eax, SYS_listen 
  mov rdi, rbx  ; l_fd
  mov esi, 16   ; backlog queue, pending connections kernel will handle while blocking
  syscall

  test rax, rax
  js  .error

  ; write(1, start_msg, len)
  mov eax, SYS_write
  mov edi, 1  ; stdout
  lea rsi, [rel start_msg]
  mov edx, start_msg_len
  syscall

; blocking accept and handle req, while(true)
.accept_loop:
  ; client_fd = accept(listen_fd, NULL, NULL)
  mov eax, SYS_accept
  mov rdi, rbx  ; l_fd
  xor esi, esi  ; 0 / NULL, no client addr needed 
  xor edx, edx
  syscall

  test rax, rax
  js  .accept_loop  ; failed, try again
  mov r12, rax  ; r12 = client_fd

  ; read(client_fd, buf, BUF_SIZE), consume the request
  mov eax, SYS_read
  mov rdi, r12        ; c_fd 
  lea rsi, [rel buf]  ; in buffer 
  mov edx, BUF_SIZE
  syscall

  test rax, rax
  jle .close    ; err || client sent nothing 
  mov r13, rax  ; r13 = bytes read (n)

  ; route request
  lea rsi, [rel buf]    ; read in buf  
  mov rdx, r13          ; rdx = n bytes 

  ; GET /health
  lea rdi, [rel health_url]
  mov ecx, health_url_len
  call prefix_match
  test eax, eax
  jnz .route_health ; match 

  lea  rsi, [rel buf]   ; reload: cmpsb advanced rsi/rdi
  mov  rdx, r13         ; rdx = n bytes
  lea  rdi, [rel index_url]
  mov  ecx, index_url_len
  call prefix_match
  test eax, eax
  jnz  .route_index

; 404 NOT FOUND
.route_not_found:
  lea  rsi, [rel not_found_response]
  mov  edx, not_found_response_len
  jmp  .send

; 200 OK / health
.route_health:
    lea  rsi, [rel health_response]
    mov  edx, health_response_len
    jmp  .send

; 200 OK / -> send index.html
.route_index:
    lea  rsi, [rel index_response]
    mov  rdx, r14
    ; falls through to .send; send (rsi = response, edx = length)

.send:
    mov  eax, SYS_sendto
    mov  rdi, r12 ; c_fd
    mov  r10d, MSG_NOSIGNAL
    xor  r8d, r8d ; 0
    xor  r9d, r9d ; 0
    syscall

.close:
  ; close(client_fd)
  mov eax, SYS_close
  mov rdi, r12
  syscall
  jmp .accept_loop  ; repeat

; save errno, print err message, exit
.error:
  neg  rax                    ; -errno -> errno
  mov  r13, rax               ; save it, the write below overwrites rax

  mov  eax, SYS_write
  mov  edi, 2                 ; stderr fd
  lea  rsi, [rel error_msg]   ; load err message
  mov  edx, error_msg_len
  syscall

  mov  edi, r13d              ; exit code = errno
  mov  eax, SYS_exit
  syscall
