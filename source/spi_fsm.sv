module spi_fsm #(
  parameter int WORD_W = 8
) (
  input  logic clk,
  input  logic rst_n,

  // control
  input  logic spi_en,
  input  logig start,// start transfer (level or pulse)
  input  logic cpol,// clock idle polarity
  input  logic cpha,// clock phase (basic support)
  input  logic sclk_tick,// one pulse per "bit step" from clk gen
  input  logic [WORD_W-1:0] tx_data,
  input  logic tx_data_valid,  // indicates tx_data is valid for LOAD

  // SPI pins
  input  logic miso,
  output logic mosi,
  output logic sclk,
  output logic cs_n,

  // status / data out
  output logic [WORD_W-1:0] rx_data,
  output logic rx_data_valid,
  output logic busy,
  output logic done
);
