//This is the modified top code that defines the class for the camera
//This is the cleaned up version. No commenting was done in this file beforehand.
//unlike the original version, it lacks an architecture definition for the clocking

/*!
 * @file Adafruit_OV2640.h
 *
 * This is documentation for Adafruit's OV2640 camera driver for the
 * Arduino platform.
 *
 * Adafruit invests time and resources providing this open source code,
 * please support Adafruit and open-source hardware by purchasing
 * products from Adafruit!
 *
 * Written by Phil "PaintYourDragon" Burgess for Adafruit Industries.
 *
 * MIT license, all text here must be included in any redistribution.
 */

#pragma once
#include "SAMD21_OV2640.h"
#include <Wire.h>

/*!
    @brief  Class encapsulating OV2640 camera functionality.
*/
class Adafruit_OV2640 {
public:
  /*!
    @brief  Constructor for Adafruit_OV2640 class.
    @param  addr      I2C address of camera.
    @param  pins_ptr  Pointer to OV2640_pins structure, describing physical
                      connection to the camera.
    @param  twi_ptr   Pointer to TwoWire instance (e.g. &Wire or &Wire1),
                      used for I2C communication with camera.

  */

  Adafruit_OV2640(uint8_t addr = OV7670_ADDR, OV2640_pins *pins_ptr = NULL,				//changed address to OV7670
                  TwoWire *twi_ptr = &Wire);//, OV2640_arch *arch_ptr = NULL);				//we define here that we will be using I2C to communicate with the camera

				  

  /*!
    @brief   Allocate and initialize resources behind an Adafruit_OV2640
             instance.
    @param   colorspace  OV2640_COLOR_RGB or OV2640_COLOR_YUV.
    @param   size        Frame size as a power-of-two reduction of VGA
                         resolution. Available sizes are OV2640_SIZE_DIV1
                         (640x480), OV2640_SIZE_DIV2 (320x240),
                         OV2640_SIZE_DIV4 (160x120), OV2640_SIZE_DIV8 and
                         OV2640_SIZE_DIV16.
    @param   fps         Desired capture framerate, in frames per second,
                         as a float up to 30.0. Actual device frame rate may
                         differ from this, depending on a host's available
                         PWM timing. Generally, the actual device fps will
                         be equal or nearest-available below the requested
                         rate, only in rare cases of extremely low requested
                         frame rates will a higher value be used. Since
                         begin() only returns a status code, if you need to
                         know the actual framerate you can call
                         OV2640_set_fps(NULL, fps) at any time before or
                         after begin() and that will return the actual
                         resulting frame rate as a float.
    @param   bufsiz      Image buffer size, in bytes. This is configurable so
                         code can do things like change image sizes without
                         reallocating (which risks losing the existing buffer)
                         or double-buffered transfers. Pass 0 to use default
                         buffer size equal to 2 bytes per pixel times the
                         number of pixels corresponding to the 'size'
                         argument. If you later call setSize() with an image
                         size exceeding the buffer size, it will fail.
    @return  Status code. OV2640_STATUS_OK on successful init.
  */
  
  OV2640_status begin();							//this is to start a specific begin function with specific imputs. Since we will run using registers, this can be left default.

  /*!
    @brief   Reads value of one register from the OV2640 camera over I2C.
    @param   reg  Register to read, from values defined in src/arch/OV2640.h.
    @return  Integer value: 0-255 (register contents) on successful read,
             -1 on error.
  */
  int readRegister(uint8_t reg);

  /*!
    @brief  Writes value of one register to the OV2640 camera over I2C.
    @param  reg    Register to read, from values defined in src/arch/OV2640.h.
    @param  value  Value to write, 0-255.

  */
  void writeRegister(uint8_t reg, uint8_t value);


private:
  TwoWire *wire;             ///< I2C interface
  OV2640_pins pins;          ///< Camera physical connections
  const uint8_t i2c_address; ///< I2C address
};

// C-ACCESSIBLE FUNCTIONS --------------------------------------------------

// These functions are declared in an extern "C" so that arch/*.c code can
// access them here. They provide a route from the mid- and low-level C code
// back up to the Arduino level, so object-based functions like
// Serial.print() and Wire.write() can be called.

extern "C" {

/*!
    @brief   Reads value of one register from the OV2640 camera over I2C.
             This is a C wrapper around the C++ readRegister() function.
    @param   obj  Pointer to Adafruit_OV2640 object (passed down to the C
                  code on init, now passed back). Adafruit_OV2640 contains
                  a pointer to a TwoWire object, allowing I2C operations
                  (via C++ class) in the lower-level C code.
    @param   reg  Register to read, from values defined in src/arch/OV2640.h.
    @return  Integer value: 0-255 (register contents) on successful read,
             -1 on error.
*/
int OV2640_read_register(void *obj, uint8_t reg);

/*!
    @brief  Writes value of one register to the OV2640 camera over I2C.
            This is a C wrapper around the C++ writeRegister() function.
    @param  obj    Pointer to Adafruit_OV2640 object (passed down to the C
                   code on init, now passed back). Adafruit_OV2640 contains
                   a pointer to a TwoWire object, allowing I2C operations
                   (via C++ class) in the lower-level C code.
    @param  reg    Register to read, from values defined in src/arch/OV2640.h.
    @param  value  Value to write, 0-255.

*/
void OV2640_write_register(void *obj, uint8_t reg, uint8_t value);

}; // end extern "C"
