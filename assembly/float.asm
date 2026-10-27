; Example of using System V ABI float asm operations
; nasm -f elf64 float.asm && ld float.o -o float && ./float; echo $?   # 8
section .data
    x   dq 2.5  ; dq = 8 byte quadword, used for long, pointers and doubles 
    y   dq 1.0

section .text
global _start

; double calc(double x, long n, double y)  ->  x * n + y
;   x -> xmm0   (1st float arg)
;   n -> rdi    (1st int arg)
;   y -> xmm1   (2nd float arg)
;   return -> xmm0
calc:
    cvtsi2sd xmm2, rdi      ; int -> double, xmm2 is free scratch
    mulsd    xmm0, xmm2     ; x * n
    addsd    xmm0, xmm1     ; + y
    ret

_start:
    movsd    xmm0, [rel x]  ; movsd = move scalar double, copies 64-bit double into low half of xmm reg
    mov      edi, 3
    movsd    xmm1, [rel y]
    call     calc           ; xmm0 = 8.5

    cvttsd2si rdi, xmm0     ; truncate to 8, used as exit code
    mov      eax, 60        ; exit
    syscall
