---
title: "sx127x"
date: 2023-01-07T16:33:18+01:00
draft: false
tags:
  - c
  - lora
  - esp32
  - embedded
  - sx127x
---
One of the fundamental questions that every programmer must periodically answer is "whether to use existing library or write your own." It's impossible to give a definitive answer to this question once and for all. You have to sit down and analyze each specific case. Recently, I faced such a situation, as I described in my [previous post]({{< ref "/lora-deep-sleep" >}}), where I explained how I reduced the LoRa current consumption to 16mA. If the goal is just to experiment and test some theory about the hardware, it was enough to modify the source code of existing [arduino-LoRa](https://github.com/sandeepmistry/arduino-LoRa). But to make such solution robust and production-ready, something more substantial is needed.

And here comes the question: should you take a ready-made library or write your own?

## Existing Libraries

I checked several libraries: [arduino-LoRa](https://github.com/sandeepmistry/arduino-LoRa), [RadioLib](https://github.com/jgromes/RadioLib), [sx127x by fifteenhex](https://github.com/fifteenhex/sx127x), [sx127x by morransmith](https://github.com/morransmith/sx127x), [esp32-lora-library](https://github.com/Inteform/esp32-lora-library), [esp-idf-sx127x](https://github.com/nopnop2002/esp-idf-sx127x), and it turned out that none of them satisfies my requirements! All of them assume that the chip should be put into sleep mode and back to idle. Essentially resetting everything that was in the FIFO buffer. But after returning from deep sleep this buffer will contain received message! Before rushing to write my own library, I could make a pull request with what I need. But even then, I'm not sure about the result: my change is too low-level and contradicts the concept of many libraries.

In general, after reviewing existing libraries for Arduino and ESP32, it seemed to me that they were written by enthusiasts who poorly understand programming. Take, for example, [arduino-LoRa](https://github.com/sandeepmistry/arduino-LoRa). A library with not a single line of comments has over 1300 stars on Github and is de facto the standard library for working with LoRa. In addition, it combines SPI initialization, working with individual pins, and the logic of controlling the sx127x chip. Surprisingly, only one method out of more than 30 returns an error code. The rest return void.

In this regard, [RadioLib](https://github.com/jgromes/RadioLib) is written slightly better. It has a separate entity called Module, which abstracts the work with SPI. However, it doesn't do it completely.

```c++
int16_t SX127x::begin(uint8_t chipVersion, uint8_t syncWord, uint16_t preambleLength) {
  // set module properties
  _mod->init(RADIOLIB_USE_SPI);
  Module::pinMode(_mod->getIrq(), INPUT);
  Module::pinMode(_mod->getGpio(), INPUT);
  ...
}
```

The ```pinMode``` method is not part of the SPI protocol, and why it was added to ```Module``` remains a mystery. In general, pin control is not part of the sx127x chip specification and should not be part of the library.

Moreover, RadioLib is an extremely convoluted library. Despite having a physical abstraction of the SPI interface called ```Module```, there is also a separate entity called ```PhysicalLayer``` in it. The class hierarchy in RadioLib is clearly overcomplicated. For example, here is how the inheritance looks:

```
PhysicalLayer -> SX127x -> SX1278 -> SX1276
```

This implies that during initialization, you need to know the chip model and create either the SX1278 or SX1276 class depending on it.

All of this turned out to be enough to start developing my own library. And it was not in vain because many blatantly strange things were revealed in many implementations.

## sx127x

To be honest, I didn't come up with the library's name right away, but from the very beginning, I knew how it should work:

 * The library should translate the chip documentation into C code. It should not make any assumptions about how it will be used or in what order its methods will be called. With this approach, working with it will be a bit more verbose, but functions can be combined as needed and called from separate threads or tasks. In my case, I can initialize access to the chip without overwriting data when coming out of deep sleep.
 * The library should be written in C and be well-documented, preferably with references to the chip documentation. Calling C from C++ is not a problem, but calling C++ from C is very difficult. Besides, I prefer C.
 * The library should not depend on other libraries. The SPI interface is available in the standard ESP library, and that's the only thing that should be needed.

As a result, I succeeded:

[https://github.com/dernasherbrezon/sx127x](https://github.com/dernasherbrezon/sx127x)

## Implementation Details

When I started working on the library, I only had a general idea of how the chip works. In short, you need to initialize the SPI device and set the necessary registers via SPI. There are many registers, and depending on the operating mode (LoRa or FSK), the same registers mean different things. However, as I worked on the library and read the documentation, I learned more and more and was increasingly amazed at how poorly designed standard libraries are.

### Header mode

It turns out that in the LoRa protocol, there is a concept of "explicit header" and "implicit header." "Explicit header" is a mode where a header is added to each message sent to the network. The receiver, in turn, receives such a header and understands the message parameters:

 * message length
 * whether checksum is used or not
 * parameters for FEC decoding

{{< svg "img/1.svg" >}}

It turns out that these parameters do not need to be configured on the receiver!

In implicit header mode, it is not transmitted, and it is assumed that the transmitter and receiver have agreed on the parameters in advance, and there is no need to transmit them. Why is such a mode needed? Well, firstly, to transmit messages faster. In some countries, there is a restriction on the time during which a signal can be transmitted in the ISM band (frequencies typically used by LoRa). The faster the message is transmitted, the more data can be transmitted in a unit of time. Secondly, by transmitting messages quickly, you can save energy.

sx127x explicitly supports both modes:

```c
/**
 * @brief Set implicit header.
 *
 * sx127x can send packets for explicit header or without it (implicit). In implicit mode receiver should be configured with pre-defined values using this function.
 * In explicit mode, all information is sent in the header. Thus no configuration needed.
 *
 * @param header Pre-defined packet information. If NULL, then assume explicit header in RX mode. For TX explicit mode please use sx127x_set_tx_explcit_header function.
 * @param device Pointer to variable to hold the device handle
 * @return
 *         - ESP_ERR_INVALID_ARG   if parameter is invalid
 *         - ESP_OK                on success
 */
esp_err_t sx127x_set_implicit_header(sx127x_implicit_header_t *header, sx127x *device);
```

### TX power

TX power configuration in sx127x chip is quite tricky. The chip has two pins to which an antenna can be connected:

 * RFO
 * PA_BOOST

{{< svg "img/2.svg" >}}

Through RFO, it is possible to achieve a power gain of 15dBm, while through PA_BOOST, it can go up to 20dBm. In the official documentation, there is a recommendation to limit the maximum current consumption for different power gain levels. I struggled for a long time to understand why this is necessary and came up with the following explanation. The power amplifier consumes current to increase the incoming signal by a factor of X. The power of the outgoing signal depends not only on the current and voltage but also on the resistance. Now imagine a situation where the antenna, with an impedance of 50 ohms, malfunctions. Or there is corrosion on the contact between the antenna and the chip. Or someone connected an antenna with 75 ohms impedance. In such cases, to achieve the same 20dBm with the same 3.3V voltage, a much higher current needs to be supplied. If the current consumption is not limited, the entire system will consume more energy at best. At worst, the chip or contacts may burn out. In the sx127x library, when configuring the power amplifier, the maximum current consumption is simultaneously limited. However, the current consumption can be overridden using a special method:

```c
/**
 * @brief Configure overload current protection (OCP) for PA.
 *
 * @param onoff Enable or disable OCP
 * @param milliamps Maximum current in milliamps
 * @param device Pointer to variable to hold the device handle
 * @return
 *         - ESP_ERR_INVALID_ARG   if parameter is invalid
 *         - ESP_OK                on success
 */
esp_err_t sx127x_set_ocp(sx127x_ocp_t onoff, uint8_t milliamps, sx127x *device);
```

### Working with interrupts

Interrupt handling, as it turns out, is one of the most complex concepts poorly implemented in almost all libraries except sx127x. The LoRa chip actively utilizes interrupts. When the chip receives a message, an interrupt is generated. When the message is sent, another interrupt is generated. When frequency hopping requires a frequency switch, yet another interrupt is generated. In LoRa chips, there are about 12 types of interrupts in total. To receive these interrupts, specific chip pins must be connected to the processor.

In most libraries, the interrupt mechanism is hidden within the library. This is extremely poor design for several reasons:

 * There is no way to handle interrupts asynchronously using FreeRTOS tasks. Typically, the implementation looks like this:
 
```c++
start = Module::micros();
while(!Module::digitalRead(_mod->getIrq())) {
  Module::yield();
  if(Module::micros() - start > timeout) {
    clearIRQFlags();
    return(ERR_TX_TIMEOUT);
  }
}
```

The SPI bus is constantly loaded with polling, the processor runs at maximum speed and consumes energy, and all other tasks are blocked. In the code above, the interrupt is not effectively handled; instead, a register is simply read to determine if the data transmission has completed.

 * The code becomes tightly coupled between the chip's logic and interrupt handling in a specific framework. In arduino-LoRa, for example, the callback function is called within the ISR. If the function takes a long time to execute or outputs to UART, the application will crash.
 
In sx127x, I decided to remove any mention of interrupts, ISRs, and FreeRTOS tasks. To configure the interrupt from the chip, the library is not needed. It is enough to write:

```c
ESP_ERROR_CHECK(gpio_isr_handler_add((gpio_num_t)DIO0, handle_interrupt_fromisr, (void *)device));
```

How the interrupt handler will be implemented should be decided by the application. It could be the same endless loop, a separate task in FreeRTOS, or something else. The main thing is that the ```sx127x_handle_interrupt``` function is called in this loop - it will process the interrupt register, understand which interrupt occurred, and call the corresponding callback.

### Error Handling

Sending or receiving data through SPI can result in an error, be it a timeout, an incorrect argument when forming a message, or something else. When working with the LoRa chip, almost every method involves sending and receiving small messages through SPI. Thus, theoretically, each method can return an error.

Since my library is written in C, I decided not to invent anything new and adopted the universally accepted error handling through return codes. That's why almost every function returns the value ```esp_err_t```. If a function is expected to return a value, it is returned through a pointer parameter.

As much as one might want to deny it, error handling always increases code size and decreases readability. The only thing that can be done is to try to ease the pain, for example, by making error handling consistent.

```c
esp_err_t code = sx127x_set_bandwidth(bw, device);
if (code != ESP_OK) {
  return code;
}
code = sx127x_set_implicit_header(NULL, device);
if (code != ESP_OK) {
  return code;
}
```

### Documentation

I noticed a peculiar feature: writing documentation contributes to writing better code. It is during the documentation process for each function that I began to understand where a function is unnecessary, where parameters need to be added, where there is no consistency, and where a complete overhaul is needed. This exercise turned out to be helpful in taking a step back and understanding what could be improved in the project.

I have read a lot of code from the standard ESP library and believe that it has very good documentation. Since my library is supported only on ESP, it made sense to format the documentation in the same style.

![](img/3.png)

### Distribution

A library that is difficult to use is of no use to anyone. That's why it is worth considering how other developers will embed it.

I faced certain difficulties with this. The thing is, before this, I only dealt with PlatformIO. In PlatformIO, a library for ESP could easily depend on the Arduino API. In theory, there is no problem with this since Espressif has released compatibility layers between ESP and Arduino, but it doesn't look neat.

In the end, I rewrote the library as follows:

 * It does not depend on the Arduino API.
 * Usage examples depend only on the ESP API.
 * The code structure corresponds to the [ESP component](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/build-system.html#example-project)

As a result, it can be used either as a component in esp-idf or as a regular library from the PlatformIO registry:

[https://registry.platformio.org/libraries/dernasherbrezon/sx127x](https://registry.platformio.org/libraries/dernasherbrezon/sx127x)

## Future plans

Surprisingly, but true: after all the work I've done, there is still room for improvement in the library.

**Firstly**, support for FSK and OOK modulations can be added. They significantly complicate the API and I haven't figured out yet how to make it simple.

**Secondly**, support for other types of interrupts can be added. I only have TTGO and Heltec boards, so I can only test interrupts on the DIO0 pin. Still, if you buy a separate module, you can use all pins and all types of interrupts. That would be fun.

**Thirdly**, abstracting the SPI operation into a separate file is possible. This would allow using the library with Raspberry PI, Arduino, or any other chip. To achieve this, it would be necessary to implement the SPI for a specific platform.
