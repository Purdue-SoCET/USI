# Universal Serial Interface

| Parameter    | Default Value | Description |
|--------------|:-------------:|-------------|
| RX_FIFO_SIZE | 16            | The number of bytes for the RX FIFO, must be a power of 2 and >= 4
| TX_FIFO_SIZE | 16            | The number of bytes for the TX FIFO, must be a power of 2 and >= 4
| CLKDIV_BITS  | 16            | The number of bits for the Clock Divisor register, determines how low of a frequency can be used

## Register Map Addresses and Summary

| Offset |       Register      | Bit Width   | Access | Description |
|--------|---------------------|:-----------:|:------:|------------|
| `0x00` | Mode Select         | 2           | R/W    | `00`=IDLE, `01`=UART, `10`=SPI, `11`=I2C |
| `0x04` | Clock Divisor       | CLKDIV_BITS | R/W    | Value to divide the clock by to get the protocol clock rate (16 bits based on UART 300 baud rate and input clock of 12.5 MHz) |
| `0x08` | Status              | 8           | R/W    | 
| `0x0C` | UART Config         | 3           | R/W    | 
| `0x10` | SPI Config          | 8           | R/W    | 
| `0x14` | I2C Config          | 1           | R/W    | 
| `0x18` | I2C Address         | 10          | R/W    | 
| `0x1C` | I2C T Low           | CLKDIV_BITS | R/W    | 
| `0x20` | I2C T High          | CLKDIV_BITS | R/W    | 
| `0x24` | Buffer Data         | 32          | R/W    | 
| `0x28` | Buffer Flush        | 2           | W      | `[1]` flush RX FIFO, `[0]` flush TX FIFO |
| `0x2C` | TX Buffer Occupancy |             | R      | Number of bytes in the TX FIFO
| `0x30` | RX Buffer Occupancy |             | R      | Number of bytes in the RX FIFO


## Common Clock Dividers (Assuming 12.5 MHz PCLK)
### UART
| Baud Rate | clkdiv |
|-----------|:------:|
| `9600`    | 1302   |
| `57600`   | 217    |
| `115200`  | 68     |

### SPI
| Frequency | clkdiv |

### I2C
| Frequency | clkdiv | tlow | thigh |