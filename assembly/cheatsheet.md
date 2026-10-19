# x86-64 Cheatsheet (NASM, Intel syntax: `op dst, src`)

## Registers
| 64 | 32 | 8 | Use |

|---|---|---|---|
| `rax` | `eax` | `al` | return, syscall # |
| `rdi` | `edi` | `dil` | arg 1 |
| `rsi` | `esi` | `sil` | arg 2 |
| `rdx` | `edx` | `dl` | arg 3, `div` high half |
| `rcx` | `ecx` | `cl` | arg 4 (calls), shift count |

| `r8`, `r9` | `r8d` | `r8b` | args 5–6 |
| `rbx`, `rbp`, `r12`–`r15` | | | callee-saved |
| `rsp` | | | stack pointer |

Writing a 32-bit reg zeroes the upper 32 bits; 8/16-bit writes don't.

## Conventions
- **Syscall:** `rax`=num, args `rdi rsi rdx r10 r8 r9`, ret `rax` (neg = `-errno`), clobbers `rcx r11`
- **Function:** args `rdi rsi rdx rcx r8 r9`, ret `rax`; `rsp` 16-byte aligned at `call`
- **Syscalls:** `read 0` · `write 1` · `open 2` · `close 3` · `exit 60`

## Instructions
| | |
|---|---|
| `mov rax, [rbx]` / `mov [rbx], rax` | load / store |
| `movzx eax, byte [rsi]` | load byte, zero-extend |
| `lea rax, [rbx+rcx*4+8]` | compute address (no load) |
| `add sub inc dec neg imul` | arithmetic |
| `div rbx` | `rdx:rax / rbx` → `rax` quot, `rdx` rem (zero `rdx` first) |
| `and or xor not shl shr sar` | bitwise / shifts |
| `cmp a, b` / `test a, b` | flags from `a-b` / `a&b` |
| `push pop call ret jmp` | stack / control |

## Jumps (after `cmp a, b`)
| | Signed | Unsigned |
|---|---|---|
| `==` / `!=` | `je` / `jne` | same |
| `<` / `<=` | `jl` / `jle` | `jb` / `jbe` |

| `>` / `>=` | `jg` / `jge` | `ja` / `jae` |


## Addressing
`[rbx]` · `[rbx+8]` · `[rbx+rcx*8+16]` · `[rel label]` · size hints: `byte word dword qword`

## Idioms
```nasm
xor eax, eax      ; zero
test rax, rax     ; jz = zero, js = negative
```

## Skeleton
```nasm
section .data
    msg db "hi", 10
    len equ $ - msg

section .bss
    buf resb 4096
section .text
    global _start

_start:
    mov rax, 1            ; write(1, msg, len)
    mov rdi, 1

    lea rsi, [rel msg]
    mov rdx, len
    syscall
    mov rax, 60           ; exit(0)
    xor edi, edi
    syscall
```
Build: `nasm -felf64 x.asm && ld x.o -o x`
