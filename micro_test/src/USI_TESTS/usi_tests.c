#include "pico/stdlib.h"
#include "hardware/spi.h"
#include "hardware/gpio.h"



void setup_spi(uint baud, spi_inst_t * spi, uint data_size)
{
    spi_init(spi, baud);
    spi_set_format(spi, data_size, SPI_CPOL_0, SPI_CPHA_0, SPI_MSB_FIRST);
    spi_set_slave(spi0, true);
}

void test_spi(spi_inst_t * spi, uint16_t * tx, uint16_t * rx, uint buff_len, int mode)
{
    switch(mode)
    {
        case 1:
            spi_write16_blocking(spi, tx, buff_len);
            break;
        case 0:
            spi_read16_blocking(spi, 0x00, rx, buff_len);
            break;
        case 2:
            spi_write16_read16_blocking(spi, tx, rx, buff_len);
        default:
            printf("incorrect test mode");
            break;
    }
}

void test_vectors()
{
    setup_spi(125000, spi1, 16);

    uint16_t * expected;
    uint16_t * rx;
    for(int i = 0; i < 16; i++)
    {
        expected[i] = i;
    }

    //test read first
    test_spi(spi1, expected, rx, 16, 0);
    for (int i = 0; i < 16; i++)
    {
        if(rx[i] != expected[i])
        {
            printf("incorrect SPI output for rx index %d", i);
        }
    }
    //test write next
    test_spi(spi1, expected, rx, 16, 1);
    //test read/write simulatenously
    test_spi(spi1, expected, rx, 16, 2);
    for (int i = 0; i < 16; i++)
    {
        if(rx[i] != expected[i])
        {
            printf("incorrect SPI output for rx index %d", i);
        }
    }
}
