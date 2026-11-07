#include "pico/stdlib.h"
#include "hardware/spi.h"
#include "hardware/gpio.h"

void setup_spi(uint baud, spi_inst_t * spi, uint data_size);

void test_spi(uint16_t * tx, uint16_t * rx, uint buff_len);

void test_vectors(void);