`timescale 1ns/1ps

// compile both interface definitions into the same simulation
interface bus_protocol_if;
    logic [31:0] addr, wdata, rdata;
    logic [3:0] strobe;
    logic wen, ren, error, request_stall;

    modport peripheral_vital (
        input addr, wdata, strobe, wen, ren,
        output rdata, error, request_stall
    );
endinterface
