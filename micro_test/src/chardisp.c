#include "pico/stdlib.h"
#include "hardware/spi.h"
#include "hardware/dma.h"
#include "hardware/gpio.h"
#include "chardisp.h"

// Make sure to set these in main.c
extern const int SPI_DISP_SCK; extern const int SPI_DISP_CSn; extern const int SPI_DISP_TX;

/***************************************************************** */

// "chardisp" stands for character display, which can be an LCD or OLED
void init_chardisp_pins() {
    // 35 TX, 33 CSn, 34 SCK
    // USING LCD!!!!!!
    // USE spio0 !~!~!
    gpio_set_function(35, GPIO_FUNC_SPI);
    gpio_set_function(34, GPIO_FUNC_SPI);
    gpio_set_function(33, GPIO_FUNC_SPI);
    spi_init(spi0, 10000u);    
    spi_set_format(spi0, 9, 0, 0, SPI_MSB_FIRST);
}

void send_spi_cmd(spi_inst_t* spi, uint16_t value) {
    while(spi_is_busy(spi)) // true = is busy
    {
        sleep_ms(1);
    } 
    spi_write16_blocking(spi, &value, 1);
}

void send_spi_data(spi_inst_t* spi, uint16_t value) {
    send_spi_cmd(spi, value | 0x100);
}

void cd_init() {
    // packets are --> 1-bit RS + 8-bit instruction/data (RS = 0 for writes)
    sleep_ms(1);
    send_spi_cmd(spi0, 0b000111100); // function set 
    sleep_us(40);
    send_spi_cmd(spi0, 0b000000001); // clear display
    sleep_ms(2);
    send_spi_cmd(spi0, 0b000000110); // entry mode set
    sleep_us(40);
}

void cd_display1(const char *str) {
    send_spi_cmd(spi0, 0b010000000); // set DRAM (0 = first line)
    for(int i = 0; i < 16; i++)
    {
        send_spi_data(spi0, str[i]);
    }
}
void cd_display2(const char *str) {
    send_spi_cmd(spi0, 0b011000000); // set DRAM (40 = start of second line)
    for(int i = 0; i < 16; i++)
    {
        send_spi_data(spi0, str[i]);
    }
}

/***************************************************************** */