#define _DEFAULT_SOURCE

#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define FDIV_BASE 0xA0000000UL
#define FPU_BASE  0xA0001000UL
#define MAP_RANGE 0x1000UL

#define FDIV_CTRL    0x00
#define FDIV_STATUS  0x04
#define FDIV_OP_A    0x08
#define FDIV_OP_B    0x0C
#define FDIV_RESULT  0x10
#define FDIV_FLAGS   0x14

#define FPU_A        0x00
#define FPU_B        0x04
#define FPU_CMD      0x08
#define FPU_RESULT   0x0C
#define FPU_STATUS   0x10

#define FPU_START    0x10U
#define OP_ADD       0U
#define OP_SUB       1U
#define OP_MUL       2U

static volatile uint32_t *fdiv_regs;
static volatile uint32_t *fpu_regs;

static uint32_t f32_to_u32(float x)
{
    union {
        float f;
        uint32_t u;
    } cvt;
    cvt.f = x;
    return cvt.u;
}

static float u32_to_f32(uint32_t x)
{
    union {
        uint32_t u;
        float f;
    } cvt;
    cvt.u = x;
    return cvt.f;
}

static void write_reg(volatile uint32_t *regs, uint32_t offset, uint32_t value)
{
    regs[offset / 4] = value;
}

static uint32_t read_reg(volatile uint32_t *regs, uint32_t offset)
{
    return regs[offset / 4];
}

static int run_fpu_op(uint32_t opcode, uint32_t a_bits, uint32_t b_bits, uint32_t *result_bits, uint32_t *status_out)
{
    uint32_t status = 0;
    int timeout = 100000;

    write_reg(fpu_regs, FPU_A, a_bits);
    write_reg(fpu_regs, FPU_B, b_bits);
    write_reg(fpu_regs, FPU_CMD, opcode);
    write_reg(fpu_regs, FPU_CMD, FPU_START | opcode);

    while (timeout-- > 0) {
        status = read_reg(fpu_regs, FPU_STATUS);
        if (status & 0x1U) {
            break;
        }
    }

    *result_bits = read_reg(fpu_regs, FPU_RESULT);
    *status_out = status;
    write_reg(fpu_regs, FPU_CMD, opcode);

    return timeout <= 0 ? -1 : 0;
}

static int run_div_op(uint32_t a_bits, uint32_t b_bits, uint32_t *result_bits, uint32_t *flags_out)
{
    uint32_t status = 0;
    int timeout = 1000000;

    write_reg(fdiv_regs, FDIV_OP_A, a_bits);
    write_reg(fdiv_regs, FDIV_OP_B, b_bits);
    write_reg(fdiv_regs, FDIV_CTRL, 1U);

    while (timeout-- > 0) {
        status = read_reg(fdiv_regs, FDIV_STATUS);
        if (status & 0x1U) {
            break;
        }
    }

    *result_bits = read_reg(fdiv_regs, FDIV_RESULT);
    *flags_out = read_reg(fdiv_regs, FDIV_FLAGS) & 0x1FU;

    return timeout <= 0 ? -1 : 0;
}

static int read_line(const char *prompt, char *buf, size_t size)
{
    printf("%s", prompt);
    fflush(stdout);
    if (fgets(buf, size, stdin) == NULL) {
        return -1;
    }
    buf[strcspn(buf, "\r\n")] = '\0';
    return 0;
}

static int read_float_prompt(const char *prompt, float *value)
{
    char line[128];
    char *endp;
    size_t i;

    if (read_line(prompt, line, sizeof(line)) != 0) {
        return -1;
    }

    for (i = 0; line[i] != '\0'; i++) {
        if (line[i] == ',') {
            line[i] = '.';
        }
    }

    errno = 0;
    *value = strtof(line, &endp);
    if (errno != 0 || endp == line) {
        printf("Invalid number: %s\n", line);
        return 1;
    }

    while (*endp != '\0') {
        if (!isspace((unsigned char)*endp)) {
            printf("Invalid trailing character in number: %s\n", line);
            return 1;
        }
        endp++;
    }

    return 0;
}

static void print_flags(uint32_t flags)
{
    printf("flags=0x%02x", flags);
    if (flags & 0x10U) {
        printf(" invalid_op");
    }
    if (flags & 0x08U) {
        printf(" div_by_zero");
    }
    if (flags & 0x04U) {
        printf(" overflow");
    }
    if (flags & 0x02U) {
        printf(" underflow");
    }
    if (flags & 0x01U) {
        printf(" inexact");
    }
    printf("\n");
}

int main(void)
{
    int fd;
    void *fdiv_map;
    void *fpu_map;
    char op_line[32];

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem failed: %s\n", strerror(errno));
        fprintf(stderr, "Run with sudo.\n");
        return 1;
    }

    fdiv_map = mmap(NULL, MAP_RANGE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FDIV_BASE);
    if (fdiv_map == MAP_FAILED) {
        fprintf(stderr, "mmap FDIV 0x%08lx failed: %s\n", FDIV_BASE, strerror(errno));
        close(fd);
        return 1;
    }

    fpu_map = mmap(NULL, MAP_RANGE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FPU_BASE);
    if (fpu_map == MAP_FAILED) {
        fprintf(stderr, "mmap FPU 0x%08lx failed: %s\n", FPU_BASE, strerror(errno));
        munmap(fdiv_map, MAP_RANGE);
        close(fd);
        return 1;
    }

    fdiv_regs = (volatile uint32_t *)fdiv_map;
    fpu_regs = (volatile uint32_t *)fpu_map;

    printf("Interactive FPU on KV260\n");
    printf("FDIV base: 0x%08lx, FPU base: 0x%08lx\n", FDIV_BASE, FPU_BASE);
    printf("Type q as operation to quit.\n\n");

    while (1) {
        float a;
        float b;
        uint32_t a_bits;
        uint32_t b_bits;
        uint32_t result_bits = 0;
        uint32_t meta = 0;
        uint32_t opcode = 0;
        char op;
        int rc;

        rc = read_float_prompt("A = ", &a);
        if (rc < 0) {
            break;
        }
        if (rc > 0) {
            continue;
        }

        if (read_line("Operation (+ - * /, q to quit) = ", op_line, sizeof(op_line)) != 0) {
            break;
        }
        op = op_line[0];
        if (op == 'q' || op == 'Q') {
            break;
        }

        rc = read_float_prompt("B = ", &b);
        if (rc < 0) {
            break;
        }
        if (rc > 0) {
            continue;
        }

        a_bits = f32_to_u32(a);
        b_bits = f32_to_u32(b);

        if (op == '+') {
            opcode = OP_ADD;
            rc = run_fpu_op(opcode, a_bits, b_bits, &result_bits, &meta);
        } else if (op == '-') {
            opcode = OP_SUB;
            rc = run_fpu_op(opcode, a_bits, b_bits, &result_bits, &meta);
        } else if (op == '*') {
            opcode = OP_MUL;
            rc = run_fpu_op(opcode, a_bits, b_bits, &result_bits, &meta);
        } else if (op == '/') {
            rc = run_div_op(a_bits, b_bits, &result_bits, &meta);
        } else {
            printf("Unknown operation: %c\n\n", op);
            continue;
        }

        if (rc != 0) {
            printf("Hardware timeout for %g %c %g\n\n", a, op, b);
            continue;
        }

        printf("HW: %g %c %g = %g\n", a, op, b, u32_to_f32(result_bits));
        printf("raw: A=0x%08x B=0x%08x RESULT=0x%08x\n", a_bits, b_bits, result_bits);
        if (op == '/') {
            print_flags(meta);
        } else {
            printf("status=0x%08x\n", meta);
        }
        printf("\n");
    }

    munmap(fpu_map, MAP_RANGE);
    munmap(fdiv_map, MAP_RANGE);
    close(fd);
    return 0;
}
