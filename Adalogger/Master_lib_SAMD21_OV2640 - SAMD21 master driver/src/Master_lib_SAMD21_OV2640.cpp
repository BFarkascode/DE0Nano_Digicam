// SPDX-FileCopyrightText: 2020 P Burgess for Adafruit Industries
//
// SPDX-License-Identifier: MIT

/*!
 * @file Adafruit_OV2640.cpp
 *
 * @mainpage Adafruit OV2640 Camera Library
 *
 * @section intro_sec Introduction
 *
 * This is documentation for Adafruit's OV2640 camera driver for the
 * Arduino platform.
 *
 * Adafruit invests time and resources providing this open source code,
 * please support Adafruit and open-source hardware by purchasing
 * products from Adafruit!
 *
 * @section dependencies Dependencies
 *
 * This library depends on
 * <a href="https://github.com/adafruit/Adafruit_ZeroDMA">
 * Adafruit_ZeroDMA</a> being present on your system. Please make sure you
 * have installed the latest version before using this library.
 *
 * @section author Author
 *
 * Written by Phil "PaintYourDragon" Burgess for Adafruit Industries.
 *
 * @section license License
 *
 * MIT license, all text here must be included in any redistribution.
 */

#include "Master_lib_SAMD21_OV2640.h"
#include <Arduino.h>
#include <Wire.h>

Adafruit_OV2640::Adafruit_OV2640(uint8_t addr, OV2640_pins *pins_ptr,
                                 TwoWire *twi_ptr)//, OV2640_arch *arch_ptr)
    : i2c_address(addr & 0x7f), wire(twi_ptr){											//we define "wire" as the I2C, we define the pointer to the TwoWire peripheral on Arduino systems
//      ,arch_defaults((arch_ptr == NULL)) {
  if (pins_ptr) {
    memcpy(&pins, pins_ptr, sizeof(OV2640_pins));										//this copies in the block memory holding the pin infromation to this level
  }
//  if (arch_ptr) {
//    memcpy(&arch, arch_ptr, sizeof(OV2640_arch));										//this copies in the block memory holding the arch infromation to this level
//  }
}


// CAMERA INIT AND CONFIG FUNCTIONS ----------------------------------------

OV2640_status Adafruit_OV2640::begin() {

  wire->begin();																		//this starts the I2C communication
  wire->setClock(100000); // Datasheet claims 400 KHz, but no, use 100 KHz				//at 100 kHz

  OV2640_host host;	
  host.pins = &pins;
  host.platform = this;
  OV2640_status status;
  status = OV2640_begin(&host);						//this is where we actually call the camera
  if (status != OV2640_STATUS_OK) {
    return status;
  }

  return status;
}

int Adafruit_OV2640::readRegister(uint8_t reg) {										//we define the read function for the class
  wire->beginTransmission(i2c_address);
  wire->write(reg);
  wire->endTransmission();
  wire->requestFrom(i2c_address, (uint8_t)1);
  return wire->read();
}

void Adafruit_OV2640::writeRegister(uint8_t reg, uint8_t value) {						//we define the write function for the class
  wire->beginTransmission(i2c_address);													//using the arrow is technically the same as wire.begin()
  wire->write(reg);
  wire->write(value);
  wire->endTransmission();
}

// C-ACCESSIBLE FUNCTIONS --------------------------------------------------

// These functions are declared in an extern "C" block in Adafruit_OV2640.h
// so that arch/*.c code can access them here. The Doxygen comments in the
// .h explain their use in more detail.

int OV2640_read_register(void *obj, uint8_t reg) {
  return ((Adafruit_OV2640 *)obj)->readRegister(reg);
}

void OV2640_write_register(void *obj, uint8_t reg, uint8_t value) {
  ((Adafruit_OV2640 *)obj)->writeRegister(reg, value);
}
