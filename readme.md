# connlimit: XDP connection limiter

This example attaches an XDP program that limits concurrent TCP connections on a given network interface.

## Prerequisites
- Linux with XDP support and libbpf headers
- Root privileges for attaching XDP programs
- Required packages (Amazon Linux / RHEL based):
  ```bash
  sudo yum install make clang bpftool libbpf-devel
  ```

## Build
```bash
make clean
make
```

The build produces the user-space loader `main` and the generated BPF skeleton `main.skel.h`.

## Run
Attach the limiter to an interface (default `ens3`). You can override the interface by passing it as the first argument.
```bash
./run.sh            # uses ens3
./run.sh eth0       # example with explicit interface
```
The helper script will:
- start the loader (`sudo ./main <iface>`)
- enforce the configured limits (port `9015`, max 200 concurrent connections)
- detach the XDP program on exit

## Manual cleanup
If the process is interrupted, ensure the interface is detached:
```bash
sudo ip link set dev <iface> xdpgeneric off
```

## Tested environment
- Kernel: Linux 6.1.158-178.288.amzn2023.x86_64 GNU/Linux

## Project layout
- `main.bpf.c` – XDP program implementing the connection limiter
- `main.c` – user-space loader using libbpf
- `run.sh` – convenience script to run and clean up the program
- `Makefile` – builds both BPF object and user-space loader
