---
title: "Compare different compilation flags for RaspberryPi"
date: 2021-09-23T21:20:18+01:00
draft: false
tags:
  - raspberrypi
  - performance
  - testing
  - dsp
---
Recently, I came across the very first version of the RaspberryPi, and I decided to experiment a bit with this old hardware.

![](/img/compare-compile-flags-raspberrypi/rpi.jpg)

I was curious about how the performance of the [volk library](https://github.com/gnuradio/volk) would differ depending on various compilation flags.

## arm1176jzf-s

Firstly, it is necessary to determine the processor. As known, RaspberryPi uses a system-on-the-chip (SoC) from Broadcom. It is even written on the processor itself: Broadcom BCM2835. Inside this chip, there are several logical components:

 * CPU core - ARM arm1176jzf-s
 * GPU core - VideoCore 4

Unfortunately, standard Linux tools provide completely incorrect information about the processor, so you have to look at the markings directly on the board and search for information on the Internet.

According to the [arm1176jzf-s specification](https://developer.arm.com/documentation/ddi0360/f/introduction-to-vfp), it does not support NEON. Therefore, there is little reason to expect significant differences in the performance of volk. Nevertheless, I wanted to dig into the numbers and try a couple of ideas.

## Compilation flags

So, based on the information about the core, I created two different sets of flags:

 * export CXXFLAGS="-mcpu=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard". By default, in Debian, all "-mfpu" flags are turned off. However, arm1176jzf-s contains the most basic extension for working with floating-point numbers - vfp. It makes sense to enable it and see how the program's speed changes.
 * export CXXFLAGS="". Default flags.
 
In addition to compiling volk with these groups of flags, I decided to test:

 * the result in Debian stretch (gcc 6.3.0)
 * the result in Debian buster (gcc 8.3.0)
 * the result compiled on RaspberryPi 3 but run it on RaspberryPi 1
 
As a test program, I chose complex number multiplication. NEON can increase speed of such test by 5 times. In this test, I did not expect any acceleration. Perhaps the only reason I chose it was that it is the most common operation in digital signal processing.

```
volk_profile -R volk_32fc_x2_dot_prod_32fc
```

## Results

I placed the test results in a table:

<table>
	<thead>
		<tr>
			<td>Flags</td>
			<td>Stretch</td>
			<td>Stretch RPi3</td>
			<td>Buster</td>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td>"-mcpu=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard"</td>
			<td>28548.9 ms</td>
			<td>28515.9 ms</td>
			<td>28669 ms</td>
		</tr>
		<tr>
			<td>""</td>
			<td><strong>28088 ms</strong></td>
			<td><strong>28022 ms</strong></td>
			<td><strong>28095.8 ms</strong></td>
		</tr>
	</tbody>
</table>

As seen from the table, there is no significant difference in execution speed. However, there is a slight acceleration when compiling without any flags, on average, by 500 ms. Perhaps the operating system has some default flags that slightly help.

Another interesting finding is that different versions of GCC give approximately the same result. Apparently, the code in both cases contains the same compiler optimizations. Or none at all.

The third finding is that the application's speed does not depend on the device on which it was compiled. This is quite an obvious conclusion, but I am glad that it was confirmed once again. This indicates that there are no hidden options and optimizations in the device firmware.