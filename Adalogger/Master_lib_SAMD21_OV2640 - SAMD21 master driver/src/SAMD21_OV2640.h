// Modified OV7670 header file to run basic functions on an OV2640 or OV7670 camera. The library does not include any clocking. That must be provided elsewhere.
//No device specification, except for the architecture
//This is the cleaned version of the code. for the one with notes, check OV2640_w_notes.h
//The original code has an "arch" section which driver the clock generator within a s SAMD51. Since we are using a SAMD21, the code was not compatible

#pragma once

//#include "arch/arch_samd.h"

#if defined(ARDUINO)
#include <Arduino.h>


#define OV2640_delay_ms(x) delay(x)															//rename delay
#define OV2640_pin_output(pin) pinMode(pin, OUTPUT);										//rename pinMode to OV2640_pin_output
#define OV2640_pin_write(pin, hi) digitalWrite(pin, hi ? 1 : 0)								//rename digitalWrite
#define OV2640_disable_interrupts() noInterrupts()											//rename noInterrupts
#define OV2640_enable_interrupts() interrupts()												//rename interrupts
#else
#include <stdint.h>

#endif // end platforms

typedef int8_t OV2640_pin;

//Constant list for the status - will change according to the function, see functions that should give back OV2640_status as an output for examples
typedef enum {
  OV2640_STATUS_OK = 0,         ///< Success
  OV2640_STATUS_ERR_MALLOC,     ///< malloc() call failed
  OV2640_STATUS_ERR_PERIPHERAL, ///< Peripheral (e.g. timer) not found
} OV2640_status;


//A construct that holds the pin connections. Each element is an OV2640_pin type - defined in the samd51_var.h

typedef struct {
  OV2640_pin enable;  ///< Also called PWDN, or set to -1 and tie to GND				//currently not used
  OV2640_pin reset;   ///< Cam reset, or set to -1 and tie to 3.3V						//currently not used
  OV2640_pin xclk;    ///< MCU clock out / cam clock in									//master clock is currently not generted using this construct
  OV2640_pin pclk;    ///< Cam clock out / MCU clock in
  OV2640_pin vsync;   ///< Also called DEN1
  OV2640_pin hsync;   ///< Also called DEN2
  OV2640_pin data[8]; ///< Camera parallel data out
  OV2640_pin sda;     ///< I2C data
  OV2640_pin scl;     ///< I2C clock
} OV2640_pins;

//A construct that holds the command - register and the value what should be sent to the register

typedef struct {
  uint8_t reg;   ///< Register address
  uint8_t value; ///< Value to store
} OV2640_command;


typedef struct {
//  OV2640_arch *arch;
  OV2640_pins *pins; ///< Physical connection to camera. This is a construct from here above.
  void *platform;    ///< Platform-specific data (e.g. Arduino C++ object). Not important here.
} OV2640_host;



#define OV2640_ADDR 0x60 //< Default I2C address for the OV2640 if unspecified. This is the one used by the Arducam.

#define OV7670_ADDR 0x21	//or 0x42

							//add new addresses if other cameras are being used!!!!

#define OV2640_REG_LAST 0xF9 //< Maximum register address			- 	 used to stop data transmission		-	 this is the address of literally the very last possible register we could write to. For OV7670, it is C9. For OV2640, it is likely going to be f9.

// C++ ACCESSIBLE FUNCTIONS ------------------------------------------------

// These are declared in an extern "C" so Arduino platform C++ code can
// access them.

#ifdef __cplusplus
extern "C" {
#endif


// Architecture- and platform-neutral initialization function.

OV2640_status OV2640_begin(OV2640_host *host);


#ifdef __cplusplus
};
#endif


//Note:
//we don't use the following enums:
//OV2640_colorspace
//OV2640_size
//OV2640_night_mode
//OV2640_pattern
//fps
//PCC
//OV2640_realloc

//we don't use the following functions:
//OV2640_Y2RGB565
//OV2640_flip
//OV2640_night
//OV2640_test_pattern
//OV2640_frame_control
//OV2640_set_fps
//OV2640_set_size
//OV2640_capture