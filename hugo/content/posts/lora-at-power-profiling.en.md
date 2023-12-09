---
title: "Power consumption in lora-at"
date: 2023-11-25T23:28:18+01:00
draft: false
chartjs: true
tags:
  - lora
  - lora-at
  - esp32
  - esp-idf
  - PPK2
---

Having thoroughly understood how [Power Profiler Kit 2 (PPK2)]({{< ref "/power-profiler-kit2" >}}) works, I decided to test power consumption under different conditions. In fact, lora-at is not such a simple application. It works with bluetooth and the sx127x chip, processes commands from the UART bus and has a deep sleep mode. So there is a plenty of things to look for.

## Measurement methodology

Before you start measuring something, you need to decide how it will be measured.

**First**, I'm going to [utilize PPK2]({{< ref "/posts/power-profiler-kit2" >}}) as much as possible. Some tests require dozens of measurements and doing them manually does not make sense. I wrote a small script that allowed me to send various AT commands to the device, and then select data from a .CSV file and group it as needed. I used the built-in logic analyzer to find when the measurement started and when it ended.

**Secondly**, some processes are fast and consume a lot of energy, and some are slow and consume little energy. In this case, it is incorrect to compare the average current consumption. Where it makes sense to compare such processes, I compared the magnitude of the charge. It is measured in coulombs. A coulomb (C) is the amount of charge passed through a cross-section of a conductor at a current of 1 A in 1 s. PPK2 integrates current over time and can very quickly display the spent charge over a selected interval. You can really feel the atmosphere of a physics lab.

**Thirdly**, there are a lot of parameters that can affect energy consumption. To do this, I fixed some and changed others. This approach allowed me to somehow compare and analyze the results. For example, for all tests I used [Heltec LoRa 32 v2](https://heltec.org/project/wifi-lora-32/), which operated at a frequency of 80 MHz.

**Fourth**, PPK2 samples at a speed of 100KHz, which generates a fairly large amount of data. It is impossible to display all these points on a graph, so I took the average over a certain interval. This does not affect the resulting value of the spent charge, but slightly smoothes the graph itself.

**Fifthly**, the energy consumption of the entire board is measured, not specific components.

## sx127x

It's probably best to start with the most basic one - the sx127x chip. It supports different types of modulation, data reception and transmission, their speed, power amplifiers and much more. I decided to measure only those that could theoretically affect energy consumption. And even after that, there were a decent number of tests.

#### Receiving data

To test the receiver, I configured a second board that sends a short message:

```
AT+LORATX=CAFE,433200012,125000,9,5,18,10,8,4,0,0,1,0
```

And the board under test receives it using the command:

```
AT+LORARX=433200012,125000,9,5,18,10,8,4,0,0,1,0
```

And the same for FSK modulation:

```
AT+FSKTX=CAFE,433200012,4800,5000,4,12AD,0,2,1,4,0,0
```

And reception:

```
AT+FSKRX=433200012,4800,5000,4,12AD,0,2,1,4,5000,20000
```

The result was the following graph:

{{< chartjs url="/static/img/lora-at-power-profiling/fsk-vs-lora.json" id="fskVsLora" title="Compare FSK and LoRa" datasource="fsk2bytes" datasourceLabel="FSK" datasource2="lora2bytes" datasource2Label="LoRa" yAxisLabel="Current" yAxisUnit="mA" xAxis="time" xAxisLabel="Time" xAxisUnit="ms" staticSrc="/static/img/lora-at-power-profiling/fskVsLora.png" >}}

It shows that:

 * LoRa processes the message much faster: **13.6**ms versus **19**ms
 * More energy efficient. Due to the processing speed, the total consumption is **511**µC versus **775**µC
 * Peak consumption is slightly lower

In fact, such a comparison is incorrect. Energy consumption directly depends on the data transfer rate. The higher the speed, the faster the message is processed and the less energy is wasted.

#### CAD mode

The sx127x has a special mode called CAD (Channel Activity Detection). It is used to optimize the power consumption of the receiver. The idea is this:

 * the receiver turns on at full power for a certain time
 * after which it goes into low-power mode and tries to analyze the received signal
 * if preamble is detected, the chip generates an interrupt and you can switch to normal receiving mode
 * if preamble is not detected, then the chip waits for some time in low power mode and returns to step 1
 
The diagram looks like this:

{{< svg "/img/lora-at-power-profiling/1.svg" >}}

According to the specification, consumption can be reduced by almost half:

<table>
<thead>
  <tr>
    <th>Bandwidth (kHz)</th>
    <th>Full Rx, IDDR_L (mA)</th>
    <th>Processing, IDDC_L (mA)</th>
  </tr>	
</thead>
<tbody>
  <tr>
    <td>7.8 to 41.7</td>
    <td>11</td>
    <td>5.2</td>
  </tr>	
  <tr>
    <td>62.5</td>
    <td>11</td>
    <td>5.6</td>
  </tr>	
  <tr>
    <td>125</td>
    <td>11.5</td>
    <td>6</td>
  </tr>	
  <tr>
    <td>250</td>
    <td>12.4</td>
    <td>6.8</td>
  </tr>	
  <tr>
    <td>500</td>
    <td>13.8</td>
    <td>8.3</td>
  </tr>	
</tbody>
</table>

CAD mode can be started using the command below:

```
AT+LORACADRX=433200012,125000,9,5,18,10,8,4,0,0,1,0
```

In the end I managed to get:

{{< chartjs url="/static/img/lora-at-power-profiling/cad.json" id="cad" title="Compare RX and CAD" datasource="cad" datasourceLabel="CAD mode" datasource2="normal" datasource2Label="RX mode" yAxisLabel="Current" yAxisUnit="mA" xAxis="time" xAxisLabel="Time" xAxisUnit="ms" staticSrc="/img/lora-at-power-profiling/cad.png" >}}

Here you can immediately see several interesting things:

 * For some reason, the current consumption in the preamble search mode is slightly higher than in RX mode
 * The difference between active and passive mode is **~6**mA, which does seem to be true at **125**kHz
 * **~2** ms elapses after exiting CAD mode and before switching back. The ESP32 needs this time to process the interrupt and switch back to CAD mode. Since CAD mode ends up going into STANDBY mode, power consumption is significantly lower. 2ms for interrupt processing is a lot. If the transmission of a message begins at this time, the receiver may miss its beginning. The checksum will not match and the entire message will not be accepted. On the other hand, in practice everything works fine.

If we compare power consumption, the CAD mode is still more efficient:

 * Charge spent **1.41**mC versus **1.52**mC in **40**ms
 * Average current **35.27**mA versus **37.85**mA

#### Sending data

Current consumption during transmit depends on:

 * transmission speed
 * modulation type
 * transmitter power
 * message length
 
To make testing easier, I sent a 255 byte message with a power of 4dbm. At the same time, I changed the transmission speed and modulation type. Here is an example command for testing FSK:

```
AT+FSKTX=000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfe,433200012,1200,5000,4,12AD,0,2,1,4,240,0
```

{{< chartjs url="/static/img/lora-at-power-profiling/fsk-baud.json" id="fskBaud" title="Power consumption for different baud rates in FSK mode" 
datasource="latencyMs" 
datasourceLabel="Time" 
yAxisLogarithmic="true"
yAxisLabel="Time"
yAxisUnit="ms"
datasource2="chargemC" 
datasource2Label="Charge" 
y2AxisLogarithmic="true"
y2AxisLabel="Charge" 
y2AxisUnit="mC"
xAxis="baud" 
xAxisLabel="Baud"
xAxisUnit="" staticSrc="/img/lora-at-power-profiling/fskBaud.png" >}}

The graph shows a clear correlation. The higher the transmission speed, the less energy is wasted. By the way, the graph around 76800 baud was not always like this. When I first measured the speed, it turned out to be half that of 38400 baud. And its increase had no effect on consumption at all. After fiddling around a bit, I found a bug in the code. When reading from the UART, uint16_t overflowed and a much lower speed was set. Oops!

When sending data in LoRa mode, everything is much more complicated. The speed can be affected by: bandwidth, spreading factor and coding rate. For example, the latter controls how many bits are used for error correction codes. The larger the number, the more reliable the transmission, but the longer it takes for the data to be transmitted.

I fixed ```coding rate=4``` and changed only the bandwidth and spreading factor:

```
AT+LORATX=000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfe,433200012,500000,6,5,18,8,0,1,0,255,4,240,0
```

{{< chartjs url="/static/img/lora-at-power-profiling/lora-bandwidth-sf.json" id="loraBandwidthSf" title="Power consumption in LoRa mode" 
datasource2="sf6" datasource2Label="sf6" 
datasource3="sf7" datasource3Label="sf7" 
datasource4="sf8" datasource4Label="sf8" 
datasource5="sf9" datasource5Label="sf9" 
datasource6="sf10" datasource6Label="sf10" 
datasource7="sf11" datasource7Label="sf11" 
datasource="sf12" datasourceLabel="sf12" 
yAxisLabel="Charge" yAxisUnit="mC" 
xAxis="bandwidth" xAxisLabel="Bandwidth" xAxisUnit="Hz" staticSrc="/img/lora-at-power-profiling/loraBandwidthSf.png" >}}

Quick analysis shows:

 * The greater the spreading factor, the longer the message is transmitted and the more energy is wasted
 * The fastest LoRa data transmission (factor 6 and 500KHz channel width) consumes more energy than the fastest FSK transmission (300Kbaud rate)

In the next test I did the opposite: I fixed the data transfer rate and changed the output power from -4 to 20.

```
AT+LORATX=CA,433200012,125000,9,5,18,8,0,1,1,0,-4,240,0
AT+LORATX=CA,433200012,125000,9,5,18,8,0,1,1,0,-3,240,0
...
AT+LORATX=CA,433200012,125000,9,5,18,8,0,1,1,0,17,240,1
AT+LORATX=CA,433200012,125000,9,5,18,8,0,1,1,0,20,240,1
```

{{< chartjs url="/static/img/lora-at-power-profiling/lora-power.json" id="loraPower" title="Power consumption under different power levels" 
datasource="avgCurrent" 
datasourceLabel="Average current" 
yAxisLabel="Average current"
yAxisUnit="mA"
datasource2="charge" 
datasource2Label="Charge" 
y2AxisLabel="Charge" 
y2AxisUnit="mC"
xAxis="level" 
xAxisLabel="Level"
xAxisUnit="" staticSrc="/img/lora-at-power-profiling/loraPower.png" >}}

I wonder why at higher power levels the graphs begin to intersect? I transmitted absolutely the same message with the same parameters. The transmission time was the same. This means that the spent charge should depend linearly on the current. But instead the relationship is nonlinear.

By the way, at 7dbm the current consumption is quite even. But at 10dbm it’s not the case. Is the internal power amplifier noisy?

{{< chartjs url="/static/img/lora-at-power-profiling/txnoise.json" id="txNoise" title="7dbm vs 10dbm" datasource="7dbm" datasourceLabel="7dbm" datasource2="10dbm" datasource2Label="10dbm" yAxisLabel="Current" yAxisUnit="mA" xAxis="time" xAxisLabel="Time" xAxisUnit="" staticSrc="/img/lora-at-power-profiling/txNoise.png" >}}

In addition to the different power levels, the chip has three different physical pins that the antenna can connect to: RFO_LF, RFO_HF and PA_BOOST. +20dbm can only be transmitted via PA_BOOST. But if you transmit +7dbm, then does it make a difference which pin to use?

```
AT+LORATX=CA,168000012,125000,9,5,18,8,0,1,1,0,7,240,0
AT+LORATX=CA,433200012,125000,9,5,18,8,0,1,1,0,7,240,0
AT+LORATX=CA,433200012,125000,9,5,18,8,0,1,1,0,7,240,1
```

{{< chartjs url="/static/img/lora-at-power-profiling/txpin.json" id="txpin" title="Power consumption on different TX pins" datasource="lf7dbm" datasourceLabel="RFO_LF" datasource2="hf7dbm" datasource2Label="RFO_HF" datasource3="boost7dbm" datasource3Label="PA_BOOST" yAxisLabel="Current" yAxisUnit="mA" xAxis="time" xAxisLabel="Time" xAxisUnit="" staticSrc="/img/lora-at-power-profiling/txpin.png" >}}

Yes, there is a difference.

 * If we compare RFO_LF and RFO_HF, we can see that the current consumption at 168 MHz is higher. Apparently, at these frequencies the antenna is [no longer matched](https://en.wikipedia.org/wiki/Standing_wave_ratio).
 * The current consumption when transmitted through a separate power amplifier and PA_BOOST pin is greater than when transmitted through RFO_HF. Probably the difference goes to powering that same amplifier. 

#### Over current protection

The chip has over current protection. Datasheet has some references to the battery, chemical components and peak current consumption. At first I didn't understand anything. After reading the theory a little, it became a little more clear. The amplifier is designed for an antenna impedance of **50** Ohms. If the impedance does not match, or has ceased to match (the antenna is rusty), then more and more current will be spent to generate a given power level. This may cause the amplifier to burn out. I compared sending a message: without protection (240mA), with a slight limitation (140mA), with a maximum limitation (45mA).

```
AT+LORATX=CA,140200012,125000,9,5,18,8,0,1,1,0,17,240,1
AT+LORATX=CA,140200012,125000,9,5,18,8,0,1,1,0,17,140,1
AT+LORATX=CA,140200012,125000,9,5,18,8,0,1,1,0,17,45,1
```

{{< chartjs url="/static/img/lora-at-power-profiling/ocp2.json" id="ocp2" title="Over current protection" datasource="ocp240" datasourceLabel="240mA" datasource2="ocp140" datasource2Label="140mA" datasource3="ocp45" datasource3Label="45mA" yAxisLabel="Current" yAxisUnit="mA" xAxis="time" xAxisLabel="Time" xAxisUnit="" staticSrc="/img/lora-at-power-profiling/ocp2.png" >}}

The board consumes a constant amount of current regardless of the installed protection. But this does not mean that the protection does not work. It may be necessary to measure the actual transmitted power at the antenna. Unfortunately, I don't have the necessary equipment to test this.

## Comparison with C++ version

As I already wrote, [lora-at](https://github.com/dernasherbrezon/lora-at) was originally implemented in C++ using libraries of different quality levels. My theory was that by rewriting the project in C, I could achieve greater efficiency and simplicity. One of the goals was achieved - assembling the project began to take less time and the size of the firmware was halved. But what about power consumption?

The operation of the sx127x chip does not depend on the selected language, but everything else may theoretically differ.

### Bluetooth connection

One of the main differences between the first version and the second is the work with bluetooth. If the first version used a C++ library on top of Bluedroid, then in the second version I used Nimble. The documentation says that Nimble is a more lightweight implementation of the BLE protocol. But is this really so? And is there a difference in speed? This is very easy to check. To do this I used the command:

```
AT+BLUETOOTH=B8:27:EB:6C:7C:F8
```

This command will do the following:

 * will start connecting to the bluetooth server at ```B8:27:EB:6C:7C:F8```
 * will search for the desired GATT service and characteristics

{{< chartjs url="/static/img/lora-at-power-profiling/ble.json" id="bluetooth2" title="Power consumption when connecting to bluetooth server" datasource="blec" datasourceLabel="C" datasource2="blecpp" datasource2Label="C++" datasource3="blec2" datasource3Label="С close to RPi" yAxisLabel="Current" yAxisUnit="mA" xAxis="time" xAxisLabel="Time" xAxisUnit="ms" staticSrc="/img/lora-at-power-profiling/bluetooth2.png" >}}

It’s worth noting here that I wasn’t always able to connect to the server! At some point I had to move the board closer to the RaspberryPI. It was then that it was discovered that the closer to the bluetooth server, the faster the connection. Even if I used different versions of the application, the connection time was very different. Which gave a strong scatter in the results. For example, from 3 meters C-code could spend **386.8** mC, and C++ would not connect at all. Or from one meter C++ spent **308.3** mC, and C-code - **150.2** mC. In general, the test turned out so-so.

### Deep sleep

Deep sleep is a special operating mode in which all peripherals are turned off and the ESP32 operates consuming a minimum amount of energy. In this mode, it is impossible to do anything useful, so deep sleep usually alternates with an active phase. In the active phase, the device performs useful operations, after which it goes back to sleep. The smaller the active phase, the less energy the device will ultimately consume. In lora-at you can configure the deep sleep interval. For example, the command below will set the configuration: after 15 seconds of inactivity, go into deep sleep mode for 15 seconds.

```
AT+DSCONFIG=15000,15000
```

During the active phase, lora-at connects to bluetooth server, receives the next power-up schedule and goes to sleep again.

{{< chartjs url="/static/img/lora-at-power-profiling/ds-cycle.json" id="dsCycle" title="Active phase" datasource="dsc" datasourceLabel="C version" datasource2="dscpp" datasource2Label="С++ version" yAxisLabel="Current" yAxisUnit="mA" xAxis="time" xAxisLabel="Time" xAxisUnit="" staticSrc="/img/lora-at-power-profiling/dsCycle.png" >}}

 * Energy consumption strongly depends on the speed of connection to the bluetooth server. Moreover, sometimes it takes 2 seconds, and sometimes 7. Because of such instability, it is difficult to draw any conclusions
 * nergy consumption varies quite a lot: from **474.6**мКл mC (C++ version) to **179.2**mC (C version)
 * C++ startup time is slightly less. **~500**ms vs  **~664**ms. However, I have never been able to get less than 7 seconds to connect using the C++ version. Perhaps it missed some bluetooth event and had to wait for a retransmission from the server.

Energy consumption in deep sleep mode is **1.7**mA. This is about a million times more than the theoretical minimum of the ESP32. I spent about 2 weeks trying to figure out what the problem was. After all the tricks, I managed to reduce the consumption to **10**µA.

### Operation at low frequencies

ESP32 can operate at both 240MHz and 80MHz. Obviously, this reduces energy consumption by running slower. But does it matter if SPI bus works at 3Mhz?

<table>
<thead>
	<tr>
		<th>Operating mode</th>
		<th>Average current consumption (C)</th>
		<th>Average current consumption (C++)</th>		
	</tr>
</thead>
<tbody>
	<tr>
		<td>240Мгц</td>
		<td>48.27</td>
		<td>73.36</td>
	</tr>
	<tr>
		<td>160Мгц</td>
		<td>35.81</td>
		<td>50.64</td>
	</tr>
	<tr>
		<td>80Мгц</td>
		<td><strong>26.38</strong></td>
		<td>39.44</td>
	</tr>
</tbody>
</table>

 * As expected, the lower the microcontroller frequency, the lower the power consumption
 * Sometimes I was able to get even lower values, but I couldn't figure out how to reproduce them

By the way, the difference between the C and C++ versions is related to how events are processed. In the C version, all processing occurs in separate FreeRTOS tasks. I'm not even using the main task:

```
I (595) main_task: Returned from app_main()
```

But the C++ version checks events in an infinite loop. If I add a similar cycle to the C version, the energy consumption will be the same:

```c
uint64_t counter = 0;
uint64_t active = 1000000;
while (true) {
  counter++;
  if (counter == active) {
    counter = 0;
    vTaskDelay(pdMS_TO_TICKS(5000));
  }
}
```

#### UART interrupt handling

I enjoyed fiddling with energy consumption so much that I decided to measure completely strange things. For example, I became interested in how much energy is spent processing the received symbol via UART. The greatly enlarged graph looks like this:

{{< chartjs url="/static/img/lora-at-power-profiling/ppk-20231126T100310.json" id="uartSymbol2" title="Power consumption of a single char" datasource="uartSymbol" datasourceLabel="Current" yAxisLabel="Current" yAxisUnit="mA" xAxis="time" xAxisLabel="Time" xAxisUnit="ms" staticSrc="/img/lora-at-power-profiling/uartSymbol2.png" >}}

 * Each press causes a jump in current consumption of approximately **10**mA and lasts approximately **1.4**ms
 * It’s not very clear why there are two jumps
 * If you put several characters into the buffer at once using CMD+V, this will generate one interrupt and a very similar graph

If **37.32** µC are spent in **1.4** ms, and **35.11** µC are spent in idle mode during the same time, then pressing the button costs **2.21** µC.

## Conclusions

 * C code is on average more energy efficient by using FreeRTOS tasks rather than an infinite loop
 * Using the energy consumption graph, you can find bugs in the code
 * Bluetooth Low Energy is not the most predictable protocol in terms of energy consumption
 * Even if the deep sleep code is called correctly, this does not guarantee that the device actually consumes little power. We need to measure!