# hal-posix — the POSIX implementation of [`hal`](https://github.com/ct-pkg/hal)

> English · [中文](#中文)

`hal-posix` implements the four `hal 1.0.0` traits on POSIX hosts: macOS and
Linux on x86_64 and aarch64, from one source tree. It publishes one public
instance, `posix_hal`, and a consumer boxes it into any of the traits.

| Trait | Implementation |
| --- | --- |
| `hal::Uart` | `send` writes fd 1 (stdout), `recv` reads fd 0 (stdin) |
| `hal::Gpio` | a 32-pin in-memory stub, one bit per pin (not real hardware) |
| `hal::Clock` | `clock_gettime(CLOCK_MONOTONIC)`; milliseconds anchored at the first call |
| `hal::Log` | writes fd 2 (stderr) |

```sh
ct get hal-posix@^1.0.0
```

```c
import Uart;
import PosixHal;

int main(void) {
    Uart u = posix_hal;
    u.send("hello\n", 6);
    return 0;
}
```

There is no `#ifdef`: every call (`write`, `read`, `clock_gettime`) is POSIX on
both platforms. A breaking change moves the version to `2.0.0`.

`now_ms` is anchored at the first call (0 on the first call), so the value stays
inside `int` for 24.8 days of process runtime rather than wrapping when the
machine's uptime passes 24.8 days. The contract only promises differences, so
this is the same behaviour for every consumer that follows it.

## 中文

`hal-posix` 在一份源码上实现 `hal 1.0.0` 的四个 trait，覆盖 macOS 与 Linux
（x86_64 / aarch64）。包内发布一个公共实例 `posix_hal`，消费方把它装箱成任意一个 trait。

| Trait | 实现 |
| --- | --- |
| `hal::Uart` | `send` 写 fd 1（stdout），`recv` 读 fd 0（stdin） |
| `hal::Gpio` | 32 针的内存桩，每针一位（不是真实硬件） |
| `hal::Clock` | `clock_gettime(CLOCK_MONOTONIC)`；毫秒，以首次调用为原点 |
| `hal::Log` | 写 fd 2（stderr） |

没有 `#ifdef`：`write` / `read` / `clock_gettime` 在两个平台上都是 POSIX。
破坏性变更走 `2.0.0`。

`now_ms` 以首次调用为原点（首次返回 0），因此值在**进程运行** 24.8 天内都不会溢出，
而不是在**机器开机** 24.8 天后回绕。契约只承诺差值，所以对任何按契约编写的调用方行为不变。

## Licence

MIT — see [LICENSE](LICENSE).
