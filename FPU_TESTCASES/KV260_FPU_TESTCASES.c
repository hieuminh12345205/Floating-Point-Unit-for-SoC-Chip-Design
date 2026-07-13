#define _DEFAULT_SOURCE

#include <errno.h>
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

typedef struct {
    const char *suite;
    const char *op_name;
    uint32_t opcode;
    const char *name;
    uint32_t a;
    uint32_t b;
    uint32_t expected;
    uint32_t expected_flags;
    uint32_t flag_mask;
} test_case_t;

static volatile uint32_t *fdiv_regs;
static volatile uint32_t *fpu_regs;

static const test_case_t add_cases[] = {
    {"add", "ADD", OP_ADD, "1.0+2.0",       0x3F800000U, 0x40000000U, 0x40400000U, 0x00U, 0x00U},
    {"add", "ADD", OP_ADD, "-1.5+3.5",      0xBFC00000U, 0x40600000U, 0x40000000U, 0x00U, 0x00U},
    {"add", "ADD", OP_ADD, "1.0+(-1.0)",    0x3F800000U, 0xBF800000U, 0x00000000U, 0x00U, 0x00U},
    {"add", "ADD", OP_ADD, "0.0+5.0",       0x00000000U, 0x40A00000U, 0x40A00000U, 0x00U, 0x00U},
    {"add", "ADD", OP_ADD, "100.0+0.25",    0x42C80000U, 0x3E800000U, 0x42C88000U, 0x00U, 0x00U},
    {"add", "ADD", OP_ADD, "-2.0+(-3.0)",   0xC0000000U, 0xC0400000U, 0xC0A00000U, 0x00U, 0x00U},
};

static const test_case_t sub_cases[] = {
    {"sub", "SUB", OP_SUB, "3.5-1.5",       0x40600000U, 0x3FC00000U, 0x40000000U, 0x00U, 0x00U},
    {"sub", "SUB", OP_SUB, "1.0-1.5",       0x3F800000U, 0x3FC00000U, 0xBF000000U, 0x00U, 0x00U},
    {"sub", "SUB", OP_SUB, "1.0-1.0",       0x3F800000U, 0x3F800000U, 0x00000000U, 0x00U, 0x00U},
    {"sub", "SUB", OP_SUB, "-1.0-1.0",      0xBF800000U, 0x3F800000U, 0xC0000000U, 0x00U, 0x00U},
    {"sub", "SUB", OP_SUB, "0.0-1.0",       0x00000000U, 0x3F800000U, 0xBF800000U, 0x00U, 0x00U},
    {"sub", "SUB", OP_SUB, "-3.0-(-1.0)",   0xC0400000U, 0xBF800000U, 0xC0000000U, 0x00U, 0x00U},
};

static const test_case_t mul_cases[] = {
    {"mul", "MUL", OP_MUL, "2.0*3.0",       0x40000000U, 0x40400000U, 0x40C00000U, 0x00U, 0x00U},
    {"mul", "MUL", OP_MUL, "1.5*2.5",       0x3FC00000U, 0x40200000U, 0x40700000U, 0x00U, 0x00U},
    {"mul", "MUL", OP_MUL, "-2.0*3.0",      0xC0000000U, 0x40400000U, 0xC0C00000U, 0x00U, 0x00U},
    {"mul", "MUL", OP_MUL, "0.0*5.0",       0x00000000U, 0x40A00000U, 0x00000000U, 0x00U, 0x00U},
    {"mul", "MUL", OP_MUL, "-1.5*(-2.0)",   0xBFC00000U, 0xC0000000U, 0x40400000U, 0x00U, 0x00U},
    {"mul", "MUL", OP_MUL, "0.5*0.25",      0x3F000000U, 0x3E800000U, 0x3E000000U, 0x00U, 0x00U},
};

static const test_case_t div_cases[] = {
    {"div", "DIV", 0U, "1.0/2.0",       0x3F800000U, 0x40000000U, 0x3F000000U, 0x00U, 0x1FU},
    {"div", "DIV", 0U, "10.0/4.0",      0x41200000U, 0x40800000U, 0x40200000U, 0x00U, 0x1FU},
    {"div", "DIV", 0U, "-6.0/3.0",      0xC0C00000U, 0x40400000U, 0xC0000000U, 0x00U, 0x1FU},
    {"div", "DIV", 0U, "1.0/3.0",       0x3F800000U, 0x40400000U, 0x3EAAAAABU, 0x01U, 0x01U},
    {"div", "DIV", 0U, "5.0/0.0",       0x40A00000U, 0x00000000U, 0x7F800000U, 0x08U, 0x08U},
    {"div", "DIV", 0U, "0.0/0.0",       0x00000000U, 0x00000000U, 0x7FC00000U, 0x10U, 0x10U},
};

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

static int suite_matches(const char *requested, const char *suite)
{
    return strcmp(requested, "all") == 0 || strcmp(requested, suite) == 0;
}

static int diagnose_fpu_wrapper(void)
{
    uint32_t a = 0x3F800000U;
    uint32_t b = 0x40000000U;
    uint32_t cmd = OP_ADD;
    uint32_t ra;
    uint32_t rb;
    uint32_t rcmd;

    printf("Diag: writing FPU wrapper registers...\n");
    write_reg(fpu_regs, FPU_A, a);
    write_reg(fpu_regs, FPU_B, b);
    write_reg(fpu_regs, FPU_CMD, cmd);
    usleep(1000);

    printf("Diag: reading FPU wrapper registers...\n");
    ra = read_reg(fpu_regs, FPU_A);
    rb = read_reg(fpu_regs, FPU_B);
    rcmd = read_reg(fpu_regs, FPU_CMD);

    printf("FPU wrapper readback: A=0x%08x B=0x%08x CMD=0x%08x\n", ra, rb, rcmd);
    if (ra == a && rb == b && (rcmd & 0x1FU) == cmd) {
        return 0;
    }

    printf("WARNING: fpu_axi_wrapper_0 readback does not match written registers.\n");
    printf("         This usually means the AXI read decoder in fpu_axi_wrapper_v1_0_S00_AXI.v is still wrong.\n");
    printf("         DIV can still be tested through fdiv_axi_lite_0, but ADD/SUB/MUL result reads may fail.\n");
    return 1;
}

static int run_fpu_case(const test_case_t *tc)
{
    uint32_t status = 0;
    uint32_t result;
    int timeout = 100000;

    write_reg(fpu_regs, FPU_A, tc->a);
    write_reg(fpu_regs, FPU_B, tc->b);
    write_reg(fpu_regs, FPU_CMD, tc->opcode);
    write_reg(fpu_regs, FPU_CMD, FPU_START | tc->opcode);

    while (timeout-- > 0) {
        status = read_reg(fpu_regs, FPU_STATUS);
        if (status & 0x1U) {
            break;
        }
    }

    result = read_reg(fpu_regs, FPU_RESULT);
    write_reg(fpu_regs, FPU_CMD, tc->opcode);

    if (timeout <= 0) {
        printf("FAIL [%s/%s/%s] timeout STATUS=0x%08x RESULT=0x%08x\n",
               tc->suite, tc->op_name, tc->name, status, result);
        return 1;
    }

    if (result == tc->expected) {
        printf("PASS [%s/%s/%s] result=0x%08x (%g) status=0x%08x\n",
               tc->suite, tc->op_name, tc->name, result, u32_to_f32(result), status);
        return 0;
    }

    printf("FAIL [%s/%s/%s]\n", tc->suite, tc->op_name, tc->name);
    printf("  A        =0x%08x (%g)\n", tc->a, u32_to_f32(tc->a));
    printf("  B        =0x%08x (%g)\n", tc->b, u32_to_f32(tc->b));
    printf("  got      result=0x%08x (%g) status=0x%08x\n", result, u32_to_f32(result), status);
    printf("  expected result=0x%08x (%g)\n", tc->expected, u32_to_f32(tc->expected));
    return 1;
}

static int run_div_case(const test_case_t *tc)
{
    uint32_t status = 0;
    uint32_t result;
    uint32_t flags;
    int timeout = 1000000;

    write_reg(fdiv_regs, FDIV_OP_A, tc->a);
    write_reg(fdiv_regs, FDIV_OP_B, tc->b);
    write_reg(fdiv_regs, FDIV_CTRL, 1U);

    while (timeout-- > 0) {
        status = read_reg(fdiv_regs, FDIV_STATUS);
        if (status & 0x1U) {
            break;
        }
    }

    if (timeout <= 0) {
        printf("FAIL [%s/%s/%s] timeout STATUS=0x%08x\n", tc->suite, tc->op_name, tc->name, status);
        return 1;
    }

    result = read_reg(fdiv_regs, FDIV_RESULT);
    flags = read_reg(fdiv_regs, FDIV_FLAGS) & 0x1FU;

    if (result == tc->expected &&
        ((flags & tc->flag_mask) == (tc->expected_flags & tc->flag_mask))) {
        printf("PASS [%s/%s/%s] result=0x%08x (%g) flags=0x%02x\n",
               tc->suite, tc->op_name, tc->name, result, u32_to_f32(result), flags);
        return 0;
    }

    printf("FAIL [%s/%s/%s]\n", tc->suite, tc->op_name, tc->name);
    printf("  A        =0x%08x (%g)\n", tc->a, u32_to_f32(tc->a));
    printf("  B        =0x%08x (%g)\n", tc->b, u32_to_f32(tc->b));
    printf("  got      result=0x%08x (%g) flags=0x%02x\n", result, u32_to_f32(result), flags);
    printf("  expected result=0x%08x (%g) flags=0x%02x mask=0x%02x\n",
           tc->expected, u32_to_f32(tc->expected), tc->expected_flags, tc->flag_mask);
    return 1;
}

static int run_cases(const char *suite, const test_case_t *cases, size_t count, int is_div)
{
    int total = 0;
    int fails = 0;
    size_t i;

    for (i = 0; i < count; i++) {
        if (!suite_matches(suite, cases[i].suite)) {
            continue;
        }
        total++;
        fails += is_div ? run_div_case(&cases[i]) : run_fpu_case(&cases[i]);
    }

    printf("SUMMARY [%s/%s]: PASS=%d FAIL=%d TOTAL=%d\n",
           is_div ? "fdiv_axi_lite_0" : "fpu_axi_wrapper_0",
           suite, total - fails, fails, total);
    return fails;
}

static void print_usage(const char *argv0)
{
    printf("Usage: %s [add|sub|mul|div|all|diag]\n", argv0);
}

int main(int argc, char **argv)
{
    const char *suite = "all";
    int fd;
    void *fdiv_map;
    void *fpu_map;
    int fails = 0;

    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    if (argc > 1) {
        if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        }
        suite = argv[1];
    }

    printf("Opening /dev/mem...\n");
    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "open /dev/mem failed: %s\n", strerror(errno));
        fprintf(stderr, "Run with sudo.\n");
        return 1;
    }

    printf("Mapping FDIV at 0x%08lx...\n", FDIV_BASE);
    fdiv_map = mmap(NULL, MAP_RANGE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FDIV_BASE);
    if (fdiv_map == MAP_FAILED) {
        fprintf(stderr, "mmap FDIV 0x%08lx failed: %s\n", FDIV_BASE, strerror(errno));
        close(fd);
        return 1;
    }

    printf("Mapping FPU at 0x%08lx...\n", FPU_BASE);
    fpu_map = mmap(NULL, MAP_RANGE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FPU_BASE);
    if (fpu_map == MAP_FAILED) {
        fprintf(stderr, "mmap FPU 0x%08lx failed: %s\n", FPU_BASE, strerror(errno));
        munmap(fdiv_map, MAP_RANGE);
        close(fd);
        return 1;
    }

    fdiv_regs = (volatile uint32_t *)fdiv_map;
    fpu_regs = (volatile uint32_t *)fpu_map;

    printf("FDIV base: 0x%08lx\n", FDIV_BASE);
    printf("FPU  base: 0x%08lx\n", FPU_BASE);
    printf("Selected suite: %s\n", suite);

    if (strcmp(suite, "diag") == 0) {
        fails = diagnose_fpu_wrapper();
    } else {
        if (strcmp(suite, "div") != 0) {
            diagnose_fpu_wrapper();
        }
        fails += run_cases(suite, add_cases, sizeof(add_cases) / sizeof(add_cases[0]), 0);
        fails += run_cases(suite, sub_cases, sizeof(sub_cases) / sizeof(sub_cases[0]), 0);
        fails += run_cases(suite, mul_cases, sizeof(mul_cases) / sizeof(mul_cases[0]), 0);
        fails += run_cases(suite, div_cases, sizeof(div_cases) / sizeof(div_cases[0]), 1);
    }

    munmap(fpu_map, MAP_RANGE);
    munmap(fdiv_map, MAP_RANGE);
    close(fd);
    return fails == 0 ? 0 : 1;
}
