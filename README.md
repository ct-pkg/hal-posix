# hal-posix — hal 契约的 POSIX 实现

## 1. 定位与边界

`hal-posix` 在 macOS / Linux 上实现 [`hal`](https://github.com/ct-pkg/hal) 的三个可装箱 trait（`Uart`、`Gpio`、`Log`），并为 `hal::Clock.nowMs()` 提供唯一实现符号 `hal_platform_now_ms`。同一份源码服务 macOS 与 Linux 的 x86_64 / aarch64，没有 `#ifdef`。

**定位：控制台替身，不是硬件驱动。** 没有串口、引脚寄存器、中断或墙钟时间；`Uart` 是 stdin/stdout，`Gpio` 是 32 位内存桩，`Log` 是 stderr。它给开发、测试和管道程序提供一组可工作的 POSIX 后端。

**能做**

- 用 trait 语法把字节写到进程 stdout、从 stdin 读字节。
- 把诊断信息写到 stderr。
- 返回单调不减的毫秒数。
- 给只需要“能读写点什么”的代码提供一个可翻转的 32 针 GPIO 桩。
- 同一个 `posix_hal` 对象可分别装箱成 `Uart`、`Gpio`、`Log`。

**不能做**

- 驱动真实硬件：没有串口、波特率、引脚、寄存器或中断。
- 替代 UART 驱动：`Uart` 没有缓冲、帧格式或超时。
- 提供墙钟时间或日期：`Clock` 只有单调时钟。
- 提供日志框架：`Log` 没有级别、时间戳或格式化。
- 在 Windows 上运行：所有调用点都是 POSIX。
- 提供线程安全的 GPIO 或时钟状态：两者都是普通进程全局变量。

## 2. 依赖与安装

当前版本 `0.1.0`，**尚未打 tag、未进索引**（`index/packages.txt` 中该行仍是注释），`ct get hal-posix` 暂时无法解析。现在请直接用源码目录构建；0.1.0 发版后再走索引流程。

`ct.pkg` 的完整内容：

```ini
name = hal-posix
version = 0.1.0
dep = hal@^0.1.0
licence = MIT
cflags = -D_POSIX_C_SOURCE=200809L
```

- **`dep = hal@^0.1.0`**：发版后 `ct get hal-posix` 会连带 vendor 契约包 `hal`，所以是“两个包”。范围语法遵循 Phase 8 子集（`^`、`~`、比较运算符、精确版本或 `*`），解析策略是 MVS——取满足条件的**最低**版本；当前版本线只有 `0.1.0`。
- **没有 `requires`**：包不设编译器版本门槛。
- **`cflags = -D_POSIX_C_SOURCE=200809L`** 是唯一构建选项。`ct build` 默认传 `-std=c99`，glibc 在该模式下会隐藏 `write` / `read` / `clock_gettime` 的声明，除非显式请求特性级别；macOS 不带也能编，但别删，它是包声明的构建配方。
- **没有 `ldflags`**：这些调用都在 libc 里。

**平台**：macOS 与 Linux（x86_64 / aarch64）。Windows 不在范围内。

**编译器**：文档中的构建与运行在 `ct v0.19.1` 上实测。`char *` 上的字面量接收者写法（`"gpio17".read()`）需要 ct 0.20.0；当前版本请用变量接收者。

未发版期间的构建命令（在 `ct-pkg` 仓库根目录，`hal/` 与 `hal-posix/` 同级）：

```sh
ct build -I hal -I hal-posix --cflags '-D_POSIX_C_SOURCE=200809L' src/main.ct -o build
```

**发版后的索引流程**（当前不可用，仅作说明）：

```sh
export CT_INDEX=/path/to/ct-pkg/index/index
ct get hal-posix      # vendored 2 package(s)
ct install            # 离线校验，打印构建命令
```

- `ct get` 通过索引把仓库按 tag 克隆到 `vendor/hal-posix`，校验摘要，并把 commit 与摘要写进 `ct.lock`；这一步需要网络。
- `ct install` 是离线的：拿 `vendor/` 和 `ct.lock` 对账，打印一条可直接运行的 `ct build` 命令，本身不编译。
- `ct verify` 也离线，只校验摘要；健康的目录会打印 `verified 2 package(s)`。

`ct install` 打印的命令形如（`<unit>.ct` 需替换为入口文件）：

```text
ct build -I vendor/hal -I vendor/hal-posix --cflags '-D_POSIX_C_SOURCE=200809L' <unit>.ct -o build
```

## 3. 快速开始

目录结构：

```text
hal-posix-demo/
├── ct.pkg
└── src/
    └── main.ct
```

消费者 `ct.pkg`（发版后使用；当前源码目录构建不需要清单）：

```ini
name = hal-posix-demo
version = 0.1.0
dep = hal-posix@^0.1.0
```

`src/main.ct`（完整文件）：

```ct
import hal::Uart;
import hal::Log;
import PosixHal;

int main(void)
{
    Uart u = posix_hal;
    Log l = posix_hal;
    char buf[64];
    int n;

    l.write("hello from hal-posix\n", 21);
    n = u.recv(buf, 64);
    if (n > 0) u.send(buf, n);
    return 0;
}
```

构建与运行（在 `ct-pkg` 仓库根目录）：

```sh
ct build -I hal -I hal-posix --cflags '-D_POSIX_C_SOURCE=200809L' hal-posix-demo/src/main.ct -o build
printf 'ping\n' | ./build
```

实测输出：

```text
hello from hal-posix
ping
```

`hello from hal-posix` 来自 `Log.write`（fd 2，stderr），`ping` 来自 `Uart.send`（fd 1，stdout）。两者都是无缓冲的 `write` 系统调用，且 `Log` 先执行，所以顺序确定。

参数说明：

- **`-I hal -I hal-posix`** 是 `import hal::Uart;` 与 `import PosixHal;` 的两个 import 根。`ct build` 自动编译被导入单元（这里生成 `main.c`、`Uart.c`、`Log.c`、`PosixHal.c`、`Gpio.c`），只写入口文件即可。
- **`--cflags '-D_POSIX_C_SOURCE=200809L'`** 来自包清单；`-std=c99` 是 `ct build` 自己的默认值。
- **`printf 'ping\n' | ./build`** 提供 stdin。不带输入运行会**阻塞**在 `recv`，直到终端送入一行或 EOF。

## 4. API 全表

包里有三种调用形态，不要混用：

| 形态 | 宿主 | 方法 | 签名 | 成功返回 | 失败 / 边界 |
| --- | --- | --- | --- | --- | --- |
| 实例 | `posix_hal` → `Uart` | `send` | `int send(char *buf, int len)` | 实际写入字节数 `0..len` | `len < 0` 或 `write` 出错返回 `-1`；短写正常 |
| 实例 | `posix_hal` → `Uart` | `recv` | `int recv(char *buf, int len)` | 实际读到字节数；EOF 为 `0` | `len < 0` 或 `read` 出错返回 `-1`；默认阻塞到至少 1 字节或 EOF |
| 实例 | `posix_hal` → `Gpio` | `read` | `int read(int pin)` | `0` 或 `1` | `pin < 0` 或 `pin >= 32` 返回 `-1` |
| 实例 | `posix_hal` → `Gpio` | `write` | `int write(int pin, int value)` | `0` | 越界返回 `-1`；`value` 非零为高 |
| `char *` 宿主 | 设备名 `"gpio<N>"` | `read` | `int read()` | `0` 或 `1` | 名字非法返回 `-1` 并置 `errno = EINVAL`；`N` 越界同样非法 |
| `char *` 宿主 | 设备名 `"gpio<N>"` | `write` | `int write(int value)` | `0` | 名字非法返回 `-1` 并置 `errno = EINVAL` |
| 命名空间 | `hal::Clock` | `nowMs` | `int nowMs()` | 单调不减的毫秒数；首次为 `0` | 无参数、无实例；`clock_gettime` 返回值未检查 |
| 实例 | `posix_hal` → `Log` | `write` | `int write(char *buf, int len)` | 实际写入字节数 | `len < 0` 或 `write` 出错返回 `-1` |

`char *` 是全仓公共映射宿主，方法名必须全仓唯一：`read` / `write` 已被本包占用；台账见仓库根的 `docs/char-host-methods.md`，守护脚本是 `tools/check-char-host.sh`。

## 5. 教程正文

### 5.1 三种形态与取舍

**实例映射（`Uart` / `Gpio` / `Log`）**

写法是 `Uart u = posix_hal;`、`Gpio g = posix_hal;`、`Log l = posix_hal;`。完整可运行示例见 3 与 6.1。

`PosixHal` 是标签对象，没有有意义的状态（`int unused` 只是占位），所有状态都在文件作用域全局变量里。三个 `map` 块都指向同一个 `posix_hal`，所以装箱后的对象到达同一组函数、同一批全局变量。

- **适合**：已有接口值、需要把后端当对象传递或多态替换的代码。
- **代价**：调用方要 import 对应 trait 并持有对象；`Clock` 因为零参能力，不走这条路。

**`char *` 宿主（`GpioName`）**

写法是 `char *dev = "gpio17"; dev.write(1); int level = dev.read();`。设备名直接当接收者，`gpio<N>` 解析成引脚号后复用 `hal_posix_gpio_read` / `hal_posix_gpio_write`。完整可运行示例见 6.2。

- **适合**：引脚号来自配置、命令行参数或字符串的代码；不用装箱、不用 import `hal::Gpio`。
- **代价**：方法名占用全仓 `char *` 命名空间；非法名字只能在运行期返回 `-1` / `EINVAL`，没有编译期检查。字面量接收者要等 ct 0.20.0。

**命名空间入口（`hal::Clock`）**

写法是 `int t0 = hal::Clock.nowMs();`。`Clock` 是零参能力，没有接收者，`hal` 用 namespace 映射把它绑到 `hal_platform_now_ms`。完整可运行示例见 6.3。

- **适合**：只需要读时间，不需要对象或多态。
- **代价**：不可装箱、不能传参、不能按实例替换；替换时钟只能整替换链接期符号 `hal_platform_now_ms`。名字写错不会在 CT 层报错，而是链接期 `undefined reference`。

### 5.2 与 hal 的对接

```text
hal（契约包）                  hal-posix（实现包）
Uart.h.ct  pub trait Uart  ── map trait Uart for instance posix_hal ──┐
Gpio.h.ct  pub trait Gpio  ── map trait Gpio for instance posix_hal ──┼─► posix_hal（唯一实例）
Log.h.ct   pub trait Log   ── map trait Log  for instance posix_hal ──┘

Clock.m.ct pub trait Clock ── map trait Clock for namespace hal ─────► hal_platform_now_ms()

应用：Uart u = posix_hal;  /  hal::Clock.nowMs();
```

`hal` 提供 trait 声明，`hal-posix` 通过 `dep` 把它拉进来。`hal-posix` 不写 `impl Uart for PosixHal`，而是用 `map` 块把 trait 方法直接指向 C 辅助函数；`Clock` 的实现符号由本包提供。契约侧细节见 [`hal` 文档](https://github.com/ct-pkg/hal)。

### 5.3 `Uart`：stdin / stdout

- `send` 向 fd 1 写最多 `len` 字节，对应一次 `write` 系统调用；短写正常，需要写满就自己循环。
- `recv` 从 fd 0 读最多 `len` 字节，对应一次 `read` 系统调用；EOF 返回 `0`，默认阻塞到至少 1 字节或 EOF。
- `len < 0` 在两个方法上都直接返回 `-1`，不发起系统调用。
- 没有缓冲、帧格式、波特率、超时、flush 或队列。fd 1 / fd 0 与进程内其它打印/读取代码共享，字节会交错。

### 5.4 `Gpio`：32 位内存桩

- 引脚 `0..31`，一个 `int` 位图，初始全零。
- `read(pin)` 返回 `0` / `1`，越界 `-1`；`write(pin, value)` 成功 `0`，越界 `-1`，`value` 非零为高。
- 设备名入口只接受严格形式 `gpio<N>`：前缀小写、`N` 为十进制数字、结果 `< 32`。`gpio32`、`gpio`、`GPIO17`、`gpio-1`、空串一律 `-1` 且 `errno = EINVAL`。
- 两个入口共用同一份位图：`dev.read()` 等于 `g.read(17)`，`posix_hal` 装箱前后的写入互相可见。
- 没有方向寄存器、上拉、边沿检测、中断或复用；并发访问没有同步。

### 5.5 `hal::Clock.nowMs()`：单调毫秒

- `clock_gettime(CLOCK_MONOTONIC)` 的毫秒值，减去进程第一次调用时记录的基准。
- 第一次调用返回 `0`，之后单调不减；只有差值有意义。
- 值是 `int`，原点在第一次调用，所以长跑进程在**运行** 24.8 天后回绕，而不是机器 uptime 超过 24.8 天时。
- 不是墙钟，没有日期；分辨率取决于 `clock_gettime`，其返回值没有检查。
- 实现符号是本包的 `int hal_platform_now_ms(void)`，签名是契约的一部分，不能改名或加参数。

### 5.6 `Log`：stderr

- 每次 `write` 向 fd 2 写最多 `len` 字节，对应一次 `write` 系统调用。
- 失败返回 `-1`，`len < 0` 返回 `-1`；无缓冲、无 flush。
- 没有级别、时间戳、前缀、过滤或轮转；不自动加换行。

### 5.7 `ct build` 做了什么

`ct build` 只编译被导入的单元。上面的快速开始会生成 `main.c`、`Uart.c`、`Log.c`、`PosixHal.c`、`Gpio.c`，然后调用 `cc`。`Clock.m.ct` 不生成 `.c`，只在消费者翻译单元里注入 `int hal_platform_now_ms(void);` 声明；定义来自 `PosixHal.c`。

## 6. 常见配方

以下完整程序均在 `ct v0.19.1` 上实际编译运行过。统一构建方式（在 `ct-pkg` 仓库根目录）：

```sh
ct build -I hal -I hal-posix --cflags '-D_POSIX_C_SOURCE=200809L' main.ct -o build
```

### 6.1 回声：读到 EOF 为止

```ct
#include <stdio.h>
#include <unistd.h>
import hal::Uart;
import hal::Log;
import PosixHal;

int write_all(Uart u, char *buf, int len)
{
    int off = 0;
    while (off < len) {
        int n = u.send(buf + off, len - off);
        if (n <= 0) return -1;
        off = off + n;
    }
    return off;
}

int main(void)
{
    Uart u = posix_hal;
    Log l = posix_hal;
    char buf[128];
    int total = 0;
    int n;

    for (;;) {
        n = u.recv(buf, 128);
        if (n < 0) { l.write("recv failed\n", 12); return 1; }
        if (n == 0) break;
        total = total + n;
        if (write_all(u, buf, n) < 0) { l.write("send failed\n", 12); return 1; }
    }
    printf("total=%d\n", total);
    return 0;
}
```

```sh
printf 'ping\npong\n' | ./build
```

实测输出：

```text
ping
pong
total=10
```

`recv` 返回 `0` 表示 stdin EOF；`write_all` 处理 `send` 短写。可以原样作为管道过滤器使用。

### 6.2 GPIO 输出与回读

```ct
#include <stdio.h>
import hal::Gpio;
import PosixHal;

int main(void)
{
    Gpio g = posix_hal;
    char *dev = "gpio17";
    char *bad = "gpio32";
    char *empty = "";

    g.write(0, 1);
    printf("pin0=%d\n", g.read(0));
    g.write(0, 0);
    printf("pin0=%d\n", g.read(0));

    dev.write(1);
    printf("gpio17=%d\n", dev.read());
    printf("gpio17-via-instance=%d\n", g.read(17));
    dev.write(0);
    printf("gpio17=%d\n", dev.read());

    printf("pin32=%d pin-1=%d gpio32=%d gpio=%d\n",
           g.read(32), g.read(-1), bad.read(), empty.read());
    return 0;
}
```

实测输出：

```text
pin0=1
pin0=0
gpio17=1
gpio17-via-instance=1
gpio17=0
pin32=-1 pin-1=-1 gpio32=-1 gpio=-1
```

每次运行都从全零位图开始；进程退出后状态不保留。

### 6.3 用 Clock 测量耗时

```ct
#include <stdio.h>
#include <unistd.h>
import hal::Clock;
import PosixHal;

int main(void)
{
    struct timespec ts;
    int t0 = hal::Clock.nowMs();

    ts.tv_sec = 0;
    ts.tv_nsec = 2000000L;   /* 2 ms */
    nanosleep(&ts, 0);

    int t1 = hal::Clock.nowMs();

    printf("t0=%d delta_ok=%d ordered=%d\n",
           t0, t1 - t0 >= 2, t1 >= t0);
    return 0;
}
```

实测输出（`delta_ok` 断言至少 2ms，`ordered` 断言单调）：

```text
t0=0 delta_ok=1 ordered=1
```

`t0` 恒为 `0`，因为 `hal_platform_now_ms` 在第一次调用时锚定原点。只使用差值，不要依赖绝对值。

### 6.4 分离诊断输出与程序输出

`Log` 写 fd 2，`Uart.send` 写 fd 1，可以各自重定向：

```sh
printf 'ping\n' | ./build 2>/dev/null   # 只看程序输出
```

实测输出：

```text
ping
```

```sh
printf 'ping\n' | ./build 1>/dev/null   # 只看诊断
```

实测输出：

```text
hello from hal-posix
```

### 6.5 只替换 Uart 的实现

`hal` 的三个可装箱 trait 彼此独立。可以让 `Uart` 用自己的内存实现，`Gpio` / `Log` 继续用 `posix_hal`，`Clock` 照旧写 `hal::Clock.nowMs()`。

`MemUart.h.ct`：

```ct
import hal::Uart;
#include <stdio.h>

#define MEMUART_CAP 128

pub struct MemUart {
    int len;
    char data[128];
} use Uart;

impl Uart for MemUart {
    int send(char *buf, int len) {
        int i;
        if (len < 0) return -1;
        if (len > MEMUART_CAP - self->len) len = MEMUART_CAP - self->len;
        for (i = 0; i < len; i = i + 1) self->data[self->len + i] = buf[i];
        self->len = self->len + len;
        return len;
    }
    int recv(char *buf, int len) {
        int i;
        if (len < 0) return -1;
        if (len > self->len) len = self->len;
        for (i = 0; i < len; i = i + 1) buf[i] = self->data[i];
        return len;
    }
}
```

`main.ct`：

```ct
#include <stdio.h>
import hal::Uart;
import hal::Gpio;
import hal::Clock;
import PosixHal;
import MemUart;

int main(void) {
    MemUart m = { .len = 0 };
    Uart u = m;
    Gpio g = posix_hal;
    int t0 = hal::Clock.nowMs();

    u.send("stored\n", 7);
    printf("mem len=%d\n", m.len);

    g.write(5, 1);
    printf("pin5=%d pin6=%d pin99=%d\n", g.read(5), g.read(6), g.read(99));

    printf("clock_start=%d\n", t0);
    return 0;
}
```

实测输出：

```text
mem len=7
pin5=1 pin6=0 pin99=-1
clock_start=0
```

### 6.6 完全替换后端

如果所有 trait 都要换成自己的实现（测试、仿真、移植），只需要实现 `hal` 的 trait，不必依赖 `hal-posix`；`Clock` 例外，定义一个 `int hal_platform_now_ms(void)` 即可。完整示例见 [`hal` 文档](https://github.com/ct-pkg/hal)。

## 7. 排错

### `ct get hal-posix` 解析不到包

原因：`0.1.0` 尚未打 tag、未进索引，索引里没有这一行。

改法：直接用源码目录构建（见第 2 节）；等 0.1.0 发版后再用 `ct get`。

### `ct check` 报 `'import' is not supported in compile mode`

```text
src/main.ct:1:1: error: 'import' is not supported in compile mode
```

原因：`ct check` 只检查单文件、无 import 的单元；任何带 `import` 的单元都会失败。

改法：用 `ct build` 验证，它会生成 C 并交给 C 编译器。

### `ct install` 报 `cannot open './ct.pkg'`

```text
$ ct get hal-posix
vendored 2 package(s)

$ ct install
ctc: cannot open './ct.pkg'
```

原因：`ct install` 读消费者清单；`ct get` 只在清单已存在时才追加 `dep` 行。

改法：先创建 `ct.pkg`（`name` 和 `version` 必填），再执行两条命令。

### 原样粘贴打印的 `ct build` 行失败

```text
sh: unit: No such file or directory
```

原因：那行是模板，结尾是 `<unit>.ct`；在 shell 里 `<unit>` 是重定向。

改法：把占位符替换成源文件路径。`ct install` 不递归子目录，`src/main.ct` 要自己传。

### `ct install` 报 `no './ct.lock'; run 'ct get' first`

```text
ctc: no './ct.lock'; run `ct get` first
```

原因：`ct install` 与 `ct verify` 都是基于 `vendor/` 与 `ct.lock` 的离线操作。

改法：先用 `ct get` 取包。

### 修改 `vendor/hal-posix` 后校验失败

```text
ctc: 'hal-posix' does not match ct.lock (vendor sha256:<vendor 目录实算值>, lock sha256:<ct.lock 记录值>)
```

原因：`vendor/` 是钉住的副本。

改法：不要编辑 `vendor/`；重新 `ct get hal-posix` 恢复。

### `ct get hal-posix` 因 GitHub 不可达而失败

```text
ctc: git fetch of 'https://github.com/ct-pkg/hal-posix' failed
```

原因：索引存的是 git URL，首次获取需要网络。

改法：恢复网络后重试；成功 `ct get` 之后，`ct install`、`ct verify`、`ct update` 都是离线的。

### 重定向了 stdout，Log 仍然出现

原因：`Log` 写 fd 2，`Uart.send` 写 fd 1。

改法：按需分别重定向（见 6.4），把诊断和程序输出分到不同文件。

### 程序没有输出，一直停着

原因：`Uart.recv` 阻塞在 fd 0，等待至少一个字节或 EOF。

改法：给 stdin 送入数据或关闭它，例如 `printf 'x\n' | ./build`，或把 fd 0 设为非阻塞。

## 8. 限制与未支持

1. **`Gpio` 是内存，不是硬件。** `hal_posix_gpio_state` 是一个全进程共享的普通 `int`。只有引脚 `0..31` 存在，其他引脚号在 `read` 和 `write` 上都返回 `-1`。没有方向寄存器、上拉、边沿检测、中断或复用。两个 trait 对象看到的是同一批位，并发访问没有同步。
2. **`Uart` 没有缓冲。** 每次 `send` / `recv` 恰好是一次 `write` / `read` 系统调用。`recv` 阻塞到至少一个字节或 EOF，短读正常。没有波特率、帧格式、超时、flush 或队列。
3. **`Uart` 是进程控制台，不是私有端口。** fd 1 和 fd 0 与任何其他打印或读取它们的代码共享，字节会交错。
4. **`Log` 只是 stderr。** 无缓冲、无级别、无时间戳、无前缀、无过滤、无轮转；不自动加换行。
5. **`hal::Clock.nowMs()` 是进程内原点的单调毫秒。** 第一次调用返回 `0`，只有差值有意义；`int` 覆盖 24.8 天运行时间。它不是墙钟，`clock_gettime` 的返回值没有检查。
6. **构建时保留 `-D_POSIX_C_SOURCE=200809L`。** 它在包的 `cflags` 里；自己编译生成的 C 漏掉它时，`write` / `read` / `clock_gettime` 可能被隐式声明或不可见。
7. **跨单元 `Drop` 不共享。** `PosixHal` 不拥有资源，也没有析构。用自己的 struct 包住 POSIX 句柄时，把 `impl Drop` 和 `struct` 放在同一单元：`ct build` 会在每个翻译单元发出私有的 `static S_Drop_drop`（在 `ct v0.19.1` 上用双单元探针验证过），一个单元里的 `delete` 用不到另一个单元写的 `Drop`。这是编译器限制。
8. **只支持 POSIX，没有 `#ifdef`。** 同一份源码服务 macOS 和 Linux 的 x86_64 / aarch64；Windows 和非 POSIX 目标不在范围内。
9. **线程安全不在承诺内。** GPIO 位图和时钟基准都是普通全局变量；需要并发安全时自己加锁或在外层串行化。
10. **接口值借用对象。** `Uart u = posix_hal;` 里的 `u` 不拥有实例；`posix_hal` 是静态的，没有生命周期问题，换成自有对象时要注意对象先于接口值存活。

## 9. 版本与变更记录

- 当前版本：`0.1.0`，**尚未打 tag、未发布到索引**（`index/packages.txt` 中仍是注释行）；发版后索引才会出现 `name version git-url tag sha256:...` 格式的一行。
- 依赖：`dep = hal@^0.1.0`；没有 `requires`；构建与运行输出在 `ct v0.19.1` 上验证。
- 变更：
  - `Clock` 改为 namespace 映射：删除了 `posix_hal` 上的实例映射，`hal::Clock.nowMs()` 直接调用 `int hal_platform_now_ms(void)`；`Clock` 不再可装箱。
  - 新增 `char *` 上的 GPIO 设备名入口 `read()` / `write(int)`，与实例写法共用同一份位图。
  - 版本文档并入本 README，`docs/tutorial.md` 已删除。
- 历史：`v1.0.0`（commit `edd925e2d091415937acc5dd34e4f44d65549d4a`）与 `v1.0.1`（commit `7a956eed8c9c0389af788cc1fb096e6aec05dbc1`）已于 2026-11-06 撤回，版本线重置为 `0.1.0`。
- `v1.0.1` 起时钟入口（当时是 `now_ms`，现在为 `hal::Clock.nowMs()`）锚定在第一次调用，所以第一次读数为 `0`，`int` 范围覆盖 24.8 天运行时间；更早的实现返回机器 uptime。
- 许可：MIT，见 [LICENSE](LICENSE)。
