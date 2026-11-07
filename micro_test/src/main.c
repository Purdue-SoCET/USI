#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "pico/stdlib.h"
#include "hardware/spi.h"
#include "queue.h"


//////////////////////////////////////////////////////////////////////////////

const char* username = "kzisko";

const bool USING_LCD = true; // Set to true if using LCD, false if using OLED, for check_wiring.
const int SEG7_DMA_CHANNEL = 1;  // Set to the correct DMA channel for the 7-segment display for Step 4 autotest.

const int SPI_7SEG_SCK = 30; // Replace with your SCK pin number for the 7-segment display
const int SPI_7SEG_CSn = 29; // Replace with your CSn pin number for the 7-segment display
const int SPI_7SEG_TX = 27; // Replace with your TX pin number for the 7-segment display

const int SPI_DISP_SCK = 34;// Replace with your SCK pin number for the LCD/OLED display
const int SPI_DISP_CSn = 33;// Replace with your CSn pin number for the LCD/OLED display
const int SPI_DISP_TX = 35;// Replace with your TX pin number for the LCD/OLED display

//////////////////////////////////////////////////////////////////////////////

void autotest();
extern KeyEvents kev;
void send_spi_cmd(spi_inst_t* spi, uint16_t value);
void send_spi_data(spi_inst_t* spi, uint16_t value);
void cd_init();
void cd_display1(const char *str);
void cd_display2(const char *str);
void init_chardisp_pins();

void display_init_bitbang();
void display_bitbang_spi();
void display_init_spi();
void display_init_dma();
void display_print();

//////////////////////////////////////////////////////////////////////////////

// When testing 7-segment display bit-banging
// #define STEP2
// When testing 7-segment display with SPI
// #define STEP3
// When testing 7-segment display with SPI and DMA
// #define STEP4
// When testing LCD/OLED display with SPI
// #define STEP5

#define USI_SPI

// Optional: Enable for PIO testing
// #define PIO_TESTING

#ifdef PIO_TESTING
#include "spi7seg.pio.h"
#endif

//////////////////////////////////////////////////////////////////////////////

// There's not much to do in this file except comment/uncomment the steps.
// Look in display.c and chardisp.c.

//////////////////////////////////////////////////////////////////////////////

int main()
{
    // Configures our microcontroller to 
    // communicate over UART through the TX/RX pins
    stdio_init_all();

    
    // Uncomment when you need to run autotest.
    // Keep this commented out until you need it
    // since it adds a lot of time to the upload process.
    // autotest();

    #ifdef STEP2
    display_init_bitbang();
    for(;;) {
        display_bitbang_spi();
    }
    #endif

    #ifdef STEP3
    display_init_spi();
    for (;;) {
        display_print();
    }
    #endif
    
    #ifdef STEP4
    display_init_spi();
    display_init_dma();
    // and that's it!  No need to do anything else...
    #endif
    
    #ifdef STEP5
    init_chardisp_pins();
    cd_init();
    cd_display1("ECE 362 is the  ");
    cd_display2("course for you! ");
    #endif

    #ifdef PIO_TESTING
    // Add your PIO testing code here
    #endif

    #ifdef USI_SPI
        test_vectors();
    #endif

    for(;;);
    return 0;
}
