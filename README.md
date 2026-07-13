# Floating Point Unit for SoC Chip Design

Đây là repository tổng hợp dự án **FPU IEEE-754 binary32 trên KV260**, hỗ trợ bốn phép toán dấu phẩy động:

- Cộng (`ADD`)
- Trừ (`SUB`)
- Nhân (`MUL`)
- Chia (`DIV`)

Hệ thống sử dụng **Zynq UltraScale+ MPSoC**, giao tiếp giữa ARM Processing System (PS) và FPGA Programmable Logic (PL) qua **AXI4-Lite**. Chương trình C chạy trên Linux ở PS để ghi toán hạng, lệnh điều khiển và đọc kết quả từ các IP phần cứng trong PL.

## Cấu trúc repository

```text
Floating Point Unit for SoC Chip Design/
|-- FPU_TESTCASES/
|-- FPU_VERILOG_CODE/
`-- README.md
```

### `FPU_TESTCASES`

Chứa các file dùng để nạp thiết kế và kiểm thử trực tiếp trên KV260:

- `design_1_wrapper.bit`: bitstream cấu hình FPGA.
- `design_1_wrapper.hwh`, `design_1_wrapper.xsa`: thông tin phần cứng được xuất từ Vivado.
- `KV260_FPU_TESTCASES.c`: chương trình chạy 24 test cố định, gồm 6 case cho mỗi phép toán.
- `KV260_FPU.c`: chương trình nhập hai số và chọn phép toán từ bàn phím.
- `load_bitstream.sh`: nạp bitstream bằng Linux FPGA Manager.
- `run_ac4_40ps.sh`: biên dịch và chạy bộ test tự động.
- `run_interactive.sh`: biên dịch và chạy chương trình nhập tay.
- `HUONG_DAN_SU_DUNG_KV260.md`: hướng dẫn thực hành chi tiết trên board.

Kết quả kiểm thử cuối cùng trên KV260:

| Phép toán | PASS | FAIL |
|---|---:|---:|
| ADD | 6 | 0 |
| SUB | 6 | 0 |
| MUL | 6 | 0 |
| DIV | 6 | 0 |
| **Tổng** | **24** | **0** |

### `FPU_VERILOG_CODE`

Chứa toàn bộ mã nguồn phần cứng viết bằng Verilog (`.v`) và các Tcl script hỗ trợ Vivado:

- `01_ADD_SUB`: mạch cộng/trừ và testbench.
- `02_MUL`: mạch nhân và testbench.
- `03_DIV_AXI`: mạch chia, bộ chia mantissa, AXI4-Lite wrapper và testbench.
- `04_FPU_AXI_WRAPPER`: wrapper AXI4-Lite cho cộng, trừ và nhân.
- `05_VIVADO_GENERATED`: các module wrapper do Vivado sinh ra cho Block Design.
- `06_VIVADO_SCRIPTS`: Tcl script đóng gói IP và thiết lập dự án.
- `README.md`: giải thích chi tiết chức năng từng file Verilog.

## Ánh xạ địa chỉ phần cứng

| Khối IP | Base address |
|---|---|
| FDIV AXI4-Lite | `0xA0000000` |
| FPU AXI wrapper | `0xA0001000` |

Các địa chỉ này phải trùng với Address Editor trong Vivado. Chương trình C mở `/dev/mem`, dùng `mmap()` để ánh xạ hai vùng địa chỉ rồi giao tiếp với IP bằng các thanh ghi AXI4-Lite.

## Chạy nhanh trên KV260

```bash
cd FPU_TESTCASES
chmod +x load_bitstream.sh run_ac4_40ps.sh run_interactive.sh
./load_bitstream.sh
./run_ac4_40ps.sh all
./run_interactive.sh
```

Sau khi nạp bitstream, trạng thái FPGA Manager phải là `operating`:

```bash
cat /sys/class/fpga_manager/fpga0/state
```

## Công cụ sử dụng

- Vivado 2022.2
- Verilog HDL
- AXI4-Lite
- AMD/Xilinx KV260
- Debian Linux trên ARM AArch64
- GCC

## Lưu ý

- Chương trình C chạy trên ARM PS; phép toán FPU thực sự được xử lý bởi logic phần cứng trong FPGA PL.
- Cần chạy chương trình với quyền phù hợp vì `/dev/mem` là vùng truy cập địa chỉ vật lý.
- Nếu thay đổi Address Editor hoặc Block Design, phải cập nhật base address trong code C và tạo lại bitstream.
