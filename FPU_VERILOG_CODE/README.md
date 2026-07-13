# TỔNG HỢP FPU CHO VIVADO

## 1. Lưu ý quan trọng

Toàn bộ **mã nguồn HDL của FPU trong thư mục này đều là Verilog `.v`**.
Không sử dụng file VHDL `.vhd` hoặc `.vhdl`.

Ngoài các file `.v`, thư mục chỉ có:

- `README.md`: tài liệu giải thích bộ mã nguồn.
- Các file `.tcl`: script hỗ trợ tạo project, mô phỏng và đóng gói IP trong Vivado.

Hai loại file trên không phải mã nguồn HDL và không làm thay đổi việc thiết kế FPU
được xây dựng hoàn toàn bằng Verilog.

## 2. Cấu trúc tổng thể

```text
PS ARM trên KV260
        |
        | AXI4-Lite
        v
AXI Interconnect
        |
        +--> fpu_axi_wrapper_0 --> cộng / trừ / nhân
        |
        +--> fdiv_axi_lite_0  --> chia
```

- `fpu_axi_wrapper_0` là instance xử lý ADD, SUB và MUL, đặt tại địa chỉ
  `0xA0001000` trong thiết kế KV260 cuối.
- `fdiv_axi_lite_0` là instance xử lý DIV, đặt tại địa chỉ `0xA0000000`.
- Các tên có hậu tố `_0` là **tên instance trong Block Design**, không phải tên
  module RTL gốc.

## 3. Ý nghĩa từng file

### `01_ADD_SUB`

#### `fpu_add_sub_fixed.v`

Mã nguồn phép cộng và trừ số thực IEEE-754 binary32. File này chứa nhiều module:

- `fpu_unpack`: tách dấu, số mũ và mantissa của toán hạng.
- `fpu_normalize`: chuẩn hóa mantissa sau khi cộng hoặc trừ.
- `fpu_round`: làm tròn theo round-to-nearest, ties-to-even.
- `fpu_pack`: ghép lại kết quả IEEE-754 32 bit.
- `fpu_add_sub`: module chính thực hiện cộng hoặc trừ.

Ngõ vào `op_sub = 0` thực hiện cộng; `op_sub = 1` thực hiện trừ.

#### `tb_fpu_add_sub_fixed.v`

Testbench cho `fpu_add_sub_fixed.v`. Bộ test gồm 51 trường hợp, kiểm tra:

- Cộng/trừ thông thường.
- Làm tròn và sticky bit.
- Số subnormal.
- `+0` và `-0`.
- Overflow và infinity.
- NaN và invalid operation.

File này phải đặt trong **Simulation Sources**, không dùng để tổng hợp phần cứng.

### `02_MUL`

#### `fpu_mul.v`

Định nghĩa module `fmul`, thực hiện phép nhân IEEE-754 binary32. Module xử lý dấu,
cộng số mũ, nhân mantissa, chuẩn hóa, làm tròn và sinh các cờ ngoại lệ.

Tên file là `fpu_mul.v`, nhưng tên module bên trong là `fmul`. Đây là module mà
AXI wrapper gọi trực tiếp.

#### `tb_fpu_mul.v`

Testbench cho module `fmul`, kiểm tra số dương, số âm, zero, infinity, NaN và một
số phép nhân thông thường. Đặt file này trong **Simulation Sources**.

### `03_DIV_AXI`

#### `fdiv_mant_divider.v`

Khối chia mantissa. Module thực hiện phép chia phần trị bằng thuật toán chia tuần
tự và tạo quotient dùng cho bước chuẩn hóa/làm tròn.

#### `fdiv_top.v`

Lõi phép chia IEEE-754 binary32. Module này:

- Phân loại toán hạng.
- Xử lý dấu và số mũ.
- Gọi `fdiv_mant_divider` để chia mantissa.
- Chuẩn hóa và làm tròn kết quả.
- Xử lý zero, infinity, NaN và chia cho zero.
- Sinh các cờ `inexact`, `underflow`, `overflow`, `div_by_zero` và `invalid_op`.

#### `fdiv_axi_lite.v`

AXI4-Lite wrapper của lõi chia. File này tạo các thanh ghi để CPU ghi toán hạng,
phát lệnh bắt đầu và đọc kết quả/cờ trạng thái.

Module gốc có tên `fdiv_axi_lite`. Khi thêm vào Block Design, Vivado thường đặt
tên instance đầu tiên là `fdiv_axi_lite_0`.

#### `fdiv_tb.v`

Testbench cho `fdiv_top`, kiểm tra phép chia thông thường và các trường hợp như
`1/3`, số âm, chia cho zero và `0/0`. Đặt trong **Simulation Sources**.

### `04_FPU_AXI_WRAPPER`

#### `fp_addsub_axi_adapter.v`

Adapter nối lõi Verilog `fpu_add_sub` với giao diện `fp_addsub` mà AXI wrapper sử
dụng. Adapter đăng ký kết quả theo clock, tạo `valid_o` và các tín hiệu báo NaN,
infinity, zero.

File này giúp toàn bộ chuỗi ADD/SUB/MUL dùng Verilog `.v`, không cần module
VHDL `fp_addsub` cũ.

#### `fpu_axi_wrapper_v1_0_S00_AXI.v`

Phần AXI4-Lite slave chính của IP ADD/SUB/MUL. File thực hiện:

- Nhận các giao dịch đọc/ghi AXI từ PS.
- Lưu A, B và CMD vào thanh ghi.
- Giải mã opcode `ADD=0`, `SUB=1`, `MUL=2`.
- Gọi `fp_addsub` hoặc `fmul`.
- Đưa RESULT và STATUS về cho chương trình C.

#### `fpu_axi_wrapper_v1_0.v`

Top-level của IP ADD/SUB/MUL. File khai báo toàn bộ cổng AXI và instantiate
`fpu_axi_wrapper_v1_0_S00_AXI`.

Khi đóng gói IP, đặt top module là `fpu_axi_wrapper_v1_0`.

### `05_VIVADO_GENERATED`

#### `design_1_fdiv_axi_lite_0_0.v`

Wrapper instance mà Vivado sinh cho `fdiv_axi_lite_0` trong Block Design.

#### `design_1_fpu_axi_wrapper_0_0.v`

Wrapper instance mà Vivado sinh cho `fpu_axi_wrapper_0` trong Block Design.

Hai file này chỉ dùng để đối chiếu cấu trúc project cũ. Khi tạo Block Design hoặc
generate output products mới, Vivado sẽ tự sinh lại; không cần import thủ công.

### `06_VIVADO_SCRIPTS`

#### `package_fpu_axi_ip.tcl`

Đóng gói bộ ADD/SUB/MUL thành IP AXI4-Lite cho chip K26 của KV260.

#### `package_fdiv_ip.tcl`

Đóng gói `fdiv_axi_lite` thành IP AXI4-Lite cho chip K26.

#### `vivado_fdiv.tcl`

Tạo project mô phỏng FDIV, thêm source/testbench và chạy simulation.

## 4. File cần thêm vào Vivado

### Mô phỏng cộng/trừ

```text
Design Sources:     01_ADD_SUB/fpu_add_sub_fixed.v
Simulation Sources: 01_ADD_SUB/tb_fpu_add_sub_fixed.v
Simulation Top:     tb_fpu_add_sub_fixed
```

### Mô phỏng nhân

```text
Design Sources:     02_MUL/fpu_mul.v
Simulation Sources: 02_MUL/tb_fpu_mul.v
Simulation Top:     fmul_tb
```

### Mô phỏng chia

```text
Design Sources:     03_DIV_AXI/fdiv_mant_divider.v
                    03_DIV_AXI/fdiv_top.v
Simulation Sources: 03_DIV_AXI/fdiv_tb.v
Simulation Top:     fdiv_tb
```

### Đóng gói IP ADD/SUB/MUL

```text
01_ADD_SUB/fpu_add_sub_fixed.v
02_MUL/fpu_mul.v
04_FPU_AXI_WRAPPER/fp_addsub_axi_adapter.v
04_FPU_AXI_WRAPPER/fpu_axi_wrapper_v1_0_S00_AXI.v
04_FPU_AXI_WRAPPER/fpu_axi_wrapper_v1_0.v
```

Top module: `fpu_axi_wrapper_v1_0`.

### Đóng gói IP DIV

```text
03_DIV_AXI/fdiv_mant_divider.v
03_DIV_AXI/fdiv_top.v
03_DIV_AXI/fdiv_axi_lite.v
```

Top module: `fdiv_axi_lite`.

## 5. Đóng gói IP bằng Tcl

Trong Vivado Tcl Console, chuyển đến thư mục `06_VIVADO_SCRIPTS` rồi chạy:

```tcl
source package_fpu_axi_ip.tcl
source package_fdiv_ip.tcl
```

Hai IP được tạo trong `06_VIVADO_SCRIPTS/ip_repo`. Thêm repository này tại:

```text
Tools > Settings > IP > Repository
```

## 6. Luồng hoạt động ngắn gọn

1. Chương trình C trên PS ghi A, B và CMD vào thanh ghi AXI.
2. AXI wrapper giải mã opcode và chọn lõi ADD/SUB/MUL hoặc DIV.
3. Lõi Verilog trong PL thực hiện phép toán IEEE-754.
4. Wrapper cập nhật RESULT, STATUS hoặc FLAGS.
5. Chương trình C đọc kết quả từ địa chỉ AXI và chuyển mã 32 bit về `float`.

Như vậy, chương trình C chỉ điều khiển và truyền dữ liệu; phép toán thực tế được
thực hiện bởi các module Verilog trong FPGA fabric.
