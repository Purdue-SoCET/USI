#include <stdio.h>
#include "pico/stdlib.h"
#include "hardware/spi.h"

void setup_spi(void)
{
    spi_init(spi1, 125000);
    spi_set_format(spi1, 8, SPI_CPOL_0, SPI_CPHA_0, SPI_MSB_FIRST);
    spi_set_slave(spi1, true);

    gpio_set_function(40, GPIO_FUNC_SPI); // RX: FPGA MOSI
    gpio_set_function(41, GPIO_FUNC_SPI); // CSn from FPGA
    gpio_set_function(42, GPIO_FUNC_SPI); // SCLK from FPGA
    gpio_set_function(43, GPIO_FUNC_SPI); // TX: FPGA MISO

    // Proton's green user LED indicates the response is queued.
    gpio_init(24);
    gpio_set_dir(24, GPIO_OUT);
    gpio_put(24, 0);
}

void test_vectors(void)
{
    setup_spi();

    // Urbana's FIFO assembles these into 0x00001234.
    const uint8_t tx[4] = {0x34, 0x12, 0x00, 0x00};
    uint8_t rx[4] = {0};

    // Queue all four response bytes before allowing the FPGA to start.
    // DR is the SPI data register. Writes enqueue bytes in its TX FIFO.
    for (int i = 0; i < 4; i++)
    {
        while (!spi_is_writable(spi1))
            tight_loop_contents();

        spi_get_hw(spi1)->dr = tx[i];
    }

    gpio_put(24, 1);
    printf("Response queued. Release Urbana BTN0 now.\n");

    // Each FPGA-generated transfer simultaneously sends and receives a byte.
    for (int i = 0; i < 4; i++)
    {
        while (!spi_is_readable(spi1))
            tight_loop_contents();

        rx[i] = (uint8_t)spi_get_hw(spi1)->dr;
    }

    gpio_put(24, 0);

    printf("Four transfers completed. FPGA sent:");
    for (int i = 0; i < 4; i++)
        printf(" %02X", (unsigned)rx[i]);
    printf("\n");
}
