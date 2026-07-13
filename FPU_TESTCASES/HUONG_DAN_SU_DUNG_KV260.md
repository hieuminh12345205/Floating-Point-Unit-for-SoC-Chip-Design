# Huong dan chay FPU tren KV260

Thu muc nay dung de nap bitstream FPU len FPGA fabric cua KV260 va chay
kiem thu 4 phep tinh IEEE 754 single-precision:

- Cong
- Tru
- Nhan
- Chia

## 1. Cac file quan trong

```text
design_1_wrapper.bit       Bitstream nap vao FPGA
design_1_wrapper.hwh       Hardware handoff, chua dia chi IP
design_1_wrapper.xsa       File export cho Vitis/PetaLinux, khong bat buoc khi chay test Linux
KV260_FPU_TESTCASES.c      Chuong trinh chay 24 testcases co dinh
KV260_FPU.c                Chuong trinh nhap so tu ban phim va chon phep tinh
load_bitstream.sh          Script nap bitstream qua Linux FPGA Manager
run_ac4_40ps.sh            Script compile va chay 24 testcases
run_ac4_4ops.sh            Alias tuong tu run_ac4_40ps.sh
run_interactive.sh         Script compile va chay chuong trinh nhap tay
```

Dia chi IP trong bitstream:

```text
FDIV base = 0xA0000000
FPU  base = 0xA0001000
```

## 2. Copy file tu Windows len KV260

Chay tren PowerShell/CMD cua Windows:

```powershell
scp -r "C:\Users\VJU-HMinh\Documents\Codex\2026-05-23\files-mentioned-by-the-user-fdiv\FPU_KV260_TESTCASES_FIXED_20260603" debian@172.16.16.49:/home/debian/VJU_HK2_2026/
```

Neu board co IP khac, thay `172.16.16.49` bang IP cua board.

## 3. SSH vao KV260

Chay tren PowerShell/CMD cua Windows:

```powershell
ssh debian@172.16.16.49
```

Sau khi dang nhap thanh cong, vao thu muc:

```bash
cd ~/VJU_HK2_2026/FPU_KV260_TESTCASES_FIXED_20260603
ls
```

## 4. Cap quyen cho script

```bash
chmod +x load_bitstream.sh run_ac4_40ps.sh run_ac4_4ops.sh run_interactive.sh
```

Neu file bi loi Windows line ending, chay them:

```bash
sed -i 's/\r$//' load_bitstream.sh run_ac4_40ps.sh run_ac4_4ops.sh run_interactive.sh
chmod +x load_bitstream.sh run_ac4_40ps.sh run_ac4_4ops.sh run_interactive.sh
```

## 5. Nap bitstream vao FPGA

Cach khuyen dung:

```bash
./load_bitstream.sh
cat /sys/class/fpga_manager/fpga0/state
```

Neu thay:

```text
operating
```

thi bitstream da duoc nap vao FPGA.

Co the nap thu cong bang cac lenh sau:

```bash
sudo cp design_1_wrapper.bit /lib/firmware/
echo design_1_wrapper.bit | sudo tee /sys/class/fpga_manager/fpga0/firmware
cat /sys/class/fpga_manager/fpga0/state
```

## 6. Chay 24 testcases co dinh

Chay tat ca 4 phep:

```bash
./run_ac4_40ps.sh all
```

Hoac:

```bash
./run_ac4_4ops.sh all
```

Ket qua dung:

```text
SUMMARY [fpu_axi_wrapper_0/all]: PASS=6 FAIL=0 TOTAL=6
SUMMARY [fpu_axi_wrapper_0/all]: PASS=6 FAIL=0 TOTAL=6
SUMMARY [fpu_axi_wrapper_0/all]: PASS=6 FAIL=0 TOTAL=6
SUMMARY [fdiv_axi_lite_0/all]: PASS=6 FAIL=0 TOTAL=6
```

Tong cong la:

```text
ADD 6 pass
SUB 6 pass
MUL 6 pass
DIV 6 pass
TOTAL 24 pass, 0 fail
```

Chay tung phep rieng:

```bash
./run_ac4_40ps.sh add
./run_ac4_40ps.sh sub
./run_ac4_40ps.sh mul
./run_ac4_40ps.sh div
```

Neu muon compile thu cong:

```bash
gcc -O0 -g -Wall -Wextra -std=c11 -o KV260_FPU_TESTCASES KV260_FPU_TESTCASES.c
sudo ./KV260_FPU_TESTCASES all
```

## 7. Chay chuong trinh nhap so tu ban phim

```bash
./run_interactive.sh
```

Hoac compile thu cong:

```bash
gcc -O0 -g -Wall -Wextra -std=c11 -o KV260_FPU KV260_FPU.c
sudo ./KV260_FPU
```

Chuong trinh se hoi:

```text
A =
Operation (+ - * /, q to quit) =
B =
```

Vi du:

```text
A = 10
Operation (+ - * /, q to quit) = /
B = 4
```

Ket qua mong doi:

```text
HW: 10 / 4 = 2.5
raw: A=0x41200000 B=0x40800000 RESULT=0x40200000
flags=0x00
```

Co the nhap so thap phan bang dau cham hoac dau phay:

```text
0.1
0,1
0.001
0,001
```

De thoat chuong trinh, tai dong operation nhap:

```text
q
```

## 8. Loi thuong gap

### Permission denied voi /dev/mem

Neu thay:

```text
open /dev/mem failed: Permission denied
Run with sudo.
```

nghia la chuong trinh chua chay bang quyen root. Dung:

```bash
sudo ./KV260_FPU_TESTCASES all
sudo ./KV260_FPU
```

### Chua nap bitstream

Neu test timeout hoac doc sai ket qua, kiem tra lai:

```bash
cat /sys/class/fpga_manager/fpga0/state
```

Neu khong phai `operating`, nap lai:

```bash
./load_bitstream.sh
```

### Kiem tra base address trong HWH

```bash
grep -i "fdiv_axi_lite_0\|fpu_axi_wrapper_0\|C_BASEADDR" design_1_wrapper.hwh
```

Dia chi dung voi code hien tai:

```text
fdiv_axi_lite_0   0xA0000000
fpu_axi_wrapper_0 0xA0001000
```

## 9. Cau ket luan bao cao

```text
The FPU bitstream was loaded onto the KV260 FPGA through Linux FPGA Manager.
The ARM processor accessed the FPU hardware through AXI memory-mapped
registers. Addition, subtraction, multiplication, and division were verified
successfully with 24/24 hardware test cases passing.
```
