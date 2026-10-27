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

## Kewords / Types

|Keyword|Bytes|Bits|C type (x86-64 Linux)|Register|
|-------|-----|----|---------------------|--------|
|byte|  1|  8|	char|	al|
|word|	2|	16|	short|	ax|
|dword|	4|	32|	int	eax|
|qword|	8|	64|	long, pointers|	rax|

## Notes

### Regiter 'sizing'
rax, eax, ax, a1 are all the same physical register, just
viewed at 64, 32, 16 and 8 bits respectively, what you use depends on the size
of the 'word' / value you intend to put in the register. Eg. writing to eax
zeros the upper 32 bits of rax. Writing to ax or al does not clobber upper bits. 

### Hardware enforced / reserved
- rsp (base stack pointer) is implicity used by push, pop, call and ret, you can
  hypothetically put data in it but it would break your stack frame immediately.
- mul/div instructions always use rdx:rax, forgetting to zero rdx can be a
classic bug for div instructions 
- variable shift counts must be in cl, eg `shl rax, cl`
- string instructions (`rep movsb`, `rep stosb`) use rdi, rsi and rcx implicity
- syscalls overwrite rcx and r11 because CPU stores the return addr and flags
there
- x86-84 has 16 total general purpose registers to use, each 64 bits wide, the
original 8 are rax, rbx, rcx, rdx, rsi, rdi, rbp, rsp with the 8 additional r8 -
r15 being added later. In practice you only get 15 due to rsp reserved for stack
pointer, or 14 if following rbp frame pointer convention. 
- There are 16 SSE/AVX vector/float registers, `xmm0-15` (128 bit) or `ymm0-15`
  (256-bit) with AVX. AVX-512 can expand this to 32 registers `xmm0-31` and mask
  registers `k0-k7`.

### Other registers not directly expoed 
- rip = instruction pointer, not writable directly, only jumps, calls and
returns change it, readable via rel addressing Eg. `lea rax, [rel msg]`
- rflags = holds conditional flags like zero, carry, sign,overflow, and is set
by arithmetic, comparisons and conditional jumps
- system registers for control, debug and MSR are kernel only, user space
programs cannot touch them 

### Conventions (ABI preferred but not hardware enforced)
- arguements go in rdi, rsi, rdx, rcx, r8, r9
- return values go in rax, rbx, r12-r15 and are callee saved, meaning functions
must restore them before returning 
- linux syscalls: 
    - sycall number goes in rax 
    - args go in rdi, rsi, rdx, r10, r8, r9 - r10 instead of rcx as syscall
    clobbers rcx
    - kernel enforces this ABI so is essentially enforced contract and mandatory
      for linux syscalls, but not technically hardware enforced, still strict 
- rbp = generally a frame pointer for nested stack frames
- pure assembly not interacting with other systems or linux syscalls need not
follow these conventions, however generally a good practice 
- For System V ABI floating point args go in `xmm0-7` and float return values
come back in `xmm0`

### User free will 
- all other non hardware enforced and non-convention recommended registers are
fair game 
- general best practices include:
    - compute the value where it will be used instead of computing elsewhere and
      moving it, less complex and more efficient 
    - know whether a value needs to survive the call, long lived values across
    functons should go in callee saved registers rbx, r12 - r15 to prevent
    getting clobbered by externel code (interfaces, syscalls)
    - short lived scratch values go in caller saced registers rax, rcx, rdx,
    r8-r11.
    - syscalls clobber rax, rcx, r11, everything else survives
    - let fixed operands claim registers first and allocate moving/variable
    values around it 
    - use comments to document register maps for clarity

