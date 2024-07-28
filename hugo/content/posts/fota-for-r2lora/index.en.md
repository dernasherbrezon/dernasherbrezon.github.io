---
title: "Creating FOTA component"
date: 2022-01-02T21:04:18+00:00
draft: false
videos: [ https://youtu.be/_DowEhVwboI ]
tags:
  - esp32
  - r2lora
---
This post continues the development cycle of the [r2lora project](https://github.com/dernasherbrezon/r2lora). Previous articles:

 * [Creating a project for ESP32]({{< ref "/programming-esp32" >}})
 * [Setting up a project in PlatformIO]({{< ref "/configuring-platformio" >}})

FOTA is an abbreviation for [Firmware-Over-The-Air](https://en.wikipedia.org/wiki/Over-the-air_update). This is a special component that updates the application if a new version is available.

## Design

Auto-update can be done in several ways:

 * The special component starts listening on TCP/UDP port. To update, you need to send the firmware to this port from any other device running on the network. Essentially a push update.
 * A special component periodically checks the central server for a new version. If there is one, then he downloads it.
 
The first method is implemented in the [ArduinoOTA](https://github.com/jandrassy/ArduinoOTA) standard library. It is used everywhere and has become the de facto standard in the microcontroller world. One of the advantages is the ease of operation: the device starts updating as soon as someone from outside sends a new version. There is no need to create a complex infrastructure for storing and delivering updates: just send the firmware from any device on the network.

But this approach has a serious drawback: another external server (for automation) or a user (manual) is needed in order to download the firmware.

I chose the second option. It is most similar to the classic way of updating packages in Debian, Ubuntu and other operating systems. APT or any other manager periodically checks the server for updates, downloads and installs them. This is how all security updates work in almost all operating systems. The disadvantages are that the firmware must be stored on a central server and the FOTA component must periodically check the availability of a new version. In my case, this is not such a big problem, since I already maintain my own APT repository. And adding a FOTA repository is not that difficult.

## FOTA repository

I decided to go with the very basic repository structure. The FOTA repository consists of two logical files:

 * r2lora.json - index file with current firmware versions for each board
 * firmware files
 
The index file has the following structure:

```json
[
    {
        "board": "ttgo-lora32-v2",
        "version": "1.1",
        "filename": "/fotatest/ttgo-lora32-v2-1.1.bin.zz",
        "size": 203984,
        "md5Checksum": "6c0931332848636087c599a1ad9c06a8"
    }
]
```

It contains an array of json objects that describe each board. Due to the fact that each board is different, the repository must store the same version of firmware for each of the boards. Each firmware is described by the following required fields:

<table>
<thead>
<tr>
<th>
Name
</th>
<th>
Description
</th>
<th>
Example
</th>
</tr>
</thead>
<tbody>
<tr>
<td>
board
</td>
<td>
Board name. Must match the board name in PlatformIO
</td>
<td>
ttgo-lora32-v2
</td>
</tr>
<tr>
<td>
version
</td>
<td>
Application version. If the current version of the application does not match the version in the repository, then the version from the repository is downloaded.
</td>
<td>
1.1
</td>
</tr>
<tr>
<td>
filename
</td>
<td>
Path to the file inside the repository. All files must be compressed using zlib.
</td>
<td>
/fota/ttgo-lora32-v2-1.1.bin.zz
</td>
</tr>
<tr>
<td>
size
</td>
<td>
Firmware file size in bytes BEFORE compression. Allows you to correctly draw a progress bar when updating.
</td>
<td>
203984
</td>
</tr>
<tr>
<td>
md5Checksum
</td>
<td>
Checksum of the firmware file BEFORE compression. Algorithm: MD5
</td>
<td>
6c0931332848636087c599a1ad9c06a8
</td>
</tr>
</tbody>
</table>

All firmware can be compressed by almost 2 times, so by default the repository can only contain compressed firmware. This saves not only space on my S3 and network, but also increases the speed of downloading new versions. This is especially important for low-power devices like the ESP32.

The FOTA repository is accessed using HTTP, so it can be deployed anywhere. In my case it is Amazon S3.

## Algorithm

First of all, the [FOTA component](https://github.com/dernasherbrezon/r2lora/blob/main/lib/fota/Fota.cpp#L13) downloads the index file.

```c++
if (!this->client->begin(hostname, port, this->indexFile)) {
  log_e("unable to begin");
  return FOTA_UNKNOWN_ERROR;
}
if (!this->lastModified.isEmpty()) {
  this->client->addHeader("If-Modified-Since", this->lastModified);
}
const char *headers[] = {"Last-Modified"};
this->client->collectHeaders(headers, 1);
int code = this->client->GET();
```

At the same time, r2lora remember the time the file was last updated. If the file has not changed, then the server should return HTTP 304. That will help saving a little on traffic and parsing the json file. To access the repository, I use the standard ```HTTPClient`` and ```HTTPClient.h``` that comes with the Arduino framework.

Next, the component must find firmware information for the current board. PlatformIO passes the name of the board during compilation via the parameter ```ARDUINO_VARIANT```.

If the information is found and the version does not match the current one, FOTA will download the firmware file from the server. The download algorithm is quite tricky. Firmware can't fully fit into memory, so it needs to be downloaded directly into the specific nvs partition using small buffer. I used special class ```Update``` from ```Update.h```. It writes the new version to a special partition on flash memory, checks the checksum of the received file and sets the new partition as boot.

In addition, the FOTA component supports a special callback method. It can be used to update progress bar on the screen.

```c++
if (this->onUpdateFunc) {
  Update.onProgress(this->onUpdateFunc);
}
```

This lambda function receives the current number of downloaded bytes and the total number of bytes as input. The output to the screen is quite trivial:

```c++
updater->setOnUpdate([](size_t current, size_t total) {
  display->setStatus("UPDATING");
  display->setProgress((uint8_t)((float)current * 100 / total));
  display->update();
});
```

Once the file is completely downloaded and the checksum is verified, its time to reboot the board:

```c++
if (reboot) {
  log_i("update completed. rebooting");
  ESP.restart();
} else {
  log_i("update completed");
}
```

## zlib

I would also like to dwell on archiving/unarchiving. ESP32 does not support [zlib](https://zlib.net). Therefore, you need to either port zlib to the ESP32 yourself, or look for a more lightweight alternative. And there it is - [miniz](https://github.com/richgel999/miniz). The great thing about that the ROM already contains an implementation of the basic functions of miniz. So using miniz does not affect the size of the firmware.

Uncompression consists of several steps. First, you need to initialize the helper structures for miniz:

```c++
tinfl_init(this->inflator);
```

Secondly, create two intermediate buffers.

```c++
uint8_t *nextCompressedBuffer = this->compressedBuffer;
uint8_t *nextUncompressedBuffer = this->uncompressedBuffer;
```

One buffer is where the compressed data needs to be written, and the other buffer is where miniz will put the decompressed data. It is important to allocate at least 32768 bytes for the output array. This is not described in the documentation, but for some reason miniz requires a buffer of this size. If you select less, then unzipping will fail with status -1.

Next is to make sure that there is enough data in the incoming buffer for work, and at the same time that there is room in the outgoing buffer for new data.

```c++
size_t inBytes = actuallyRead;
size_t outBytes = availableOut;
status = tinfl_decompress(inflator, (const mz_uint8 *)nextCompressedBuffer, &inBytes,
                          this->uncompressedBuffer, nextUncompressedBuffer, &outBytes,
                          flags);
actuallyRead -= inBytes;
nextCompressedBuffer = nextCompressedBuffer + inBytes;

availableOut -= outBytes;
nextUncompressedBuffer = nextUncompressedBuffer + outBytes;
```

Once the outgoing buffer is completely full, it can written to flash:

```c++
size_t actuallyWrote = Update.write(this->uncompressedBuffer, bytesInTheOutput);
```

However, when I ran the test, I received the following error:

```
[I][Fota.cpp:191] downloadAndApplyFirmware(): downloading new firmware: 203984 bytes
***ERROR*** A stack overflow in task loopTask has been detected.
abort() was called at PC 0x40088a50 on core 1

ELF file SHA256: 0000000000000000

Backtrace: 0x400887bc:0x3ffaee10 0x40088a39:0x3ffaee30 0x40088a50:0x3ffaee50 0x4008a633:0x3ffaee70 0x4008c1fc:0x3ffaee90 0x4008c1b2:0x00a42700
  #0  0x400887bc:0x3ffaee10 in invoke_abort at /home/runner/work/esp32-arduino-lib-builder/esp32-arduino-lib-builder/esp-idf/components/esp32/panic.c:715
  #1  0x40088a39:0x3ffaee30 in abort at /home/runner/work/esp32-arduino-lib-builder/esp32-arduino-lib-builder/esp-idf/components/esp32/panic.c:715
  #2  0x40088a50:0x3ffaee50 in vApplicationStackOverflowHook at /home/runner/work/esp32-arduino-lib-builder/esp32-arduino-lib-builder/esp-idf/components/esp32/panic.c:715
  #3  0x4008a633:0x3ffaee70 in vTaskSwitchContext at /home/runner/work/esp32-arduino-lib-builder/esp32-arduino-lib-builder/esp-idf/components/freertos/tasks.c:3507
  #4  0x4008c1fc:0x3ffaee90 in _frxt_dispatch at /home/runner/work/esp32-arduino-lib-builder/esp32-arduino-lib-builder/esp-idf/components/freertos/portasm.S:406
  #5  0x4008c1b2:0x00a42700 in _frxt_int_exit at /home/runner/work/esp32-arduino-lib-builder/esp32-arduino-lib-builder/esp-idf/components/freertos/portasm.S:206
```

How is that possible to receive ```stack overflow``` here? I don't even have recursion. It turns out you can't initialize like this:

```c++
tinfl_decompressor inflator;
```

This will create a structure on the function call stack. And the size of this structure is larger than the available stack memory. Microcontrollers. For the same reason you cannot write:

```c++
uint8_t uncompressedBuffer[32768];
```

Otherwise it will be:

```
[E][WiFiClient.cpp:62] fillBuffer(): Not enough memory to allocate buffer
[E][WiFiClient.cpp:439] read(): fail on fd 61, errno: 11, "No more processes"
Guru Meditation Error: Core  1 panic'ed (LoadProhibited). Exception was unhandled.
```

The solution is simple - you need to allocate objects in heap using malloc or new.

After I fixed all these exceptions, I discovered that zlib is not the same as gzip. They have different headers. Therefore, creating firmware with the following command simply will not work:

```bash
gzip firmware.bin
```

miniz will not be able to unpack. The inside is still the same Deflate, but the file headers are different. You can use various hacks and replace the gzip header, but I found this unreliable. Instead I used a special program called [pigz](https://zlib.net/pigz/) that can create zlib files:

```bash
pigz --zlib firmware.bin
```

A little inconvenient, but it works.

## Testing

Code needs to be tested, and FOTA is no exception. But how can you test updating yourself? After all, after the update you need to restart the program and the test result will definitely disappear. Here I made some exceptions to the classic unit testing:

 * I added special parameter ```bool reboot``` into the ```loop``` function. It will be used for testing
 * ```loop``` function now return status code. Most of C functions return status code anyway. On the other hand this is redundant for C++ program.
 
Another difficulty in testing FOTA is a strong dependency on infrastructure. You need to make sure that the HTTP client is properly initialized and actually downloads the firmware. You need to make sure that zlib unpacks the file and the checksum matches. "If you need to test the infrastructure, then you need to create the infrastructure!" - I thought and created:

 * special firmware versions for each of the boards that do nothing.
 * uploaded them to S3
 * added many index files with various possible errors

An example unit test is below:

```c++
void test_non_existing_file() {
  Fota fota;
  fota.init("1.0", "apt.leosatdata.com", 80, "/fotatest/missingfile.json", 24 * 60 * 60 * 1000, ARDUINO_VARIANT);
  TEST_ASSERT_EQUAL(FOTA_INVALID_SERVER_RESPONSE, fota.loop(false));
}
```

FOTA initializes and attempts to check for an update. ```missingfile.json``` is a pre-generated file with an expected error that I uploaded to S3.

Another inconvenience was connecting to WiFi before performing the test. After all, in order to download from S3 you need a fully initialized Internet connection. PlatformIO allows you to pass environment variables to the build:

```
build_flags = -DWIFI_SSID=\"${sysenv.WIFI_SSID}\" -DWIFI_PASSWORD=\"${sysenv.WIFI_PASSWORD}\"
```

They are used in the code as follows:

```c++
#ifndef WIFI_SSID
#define WIFI_SSID ""
#endif

#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD ""
#endif

WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
while (WiFi.status() != WL_CONNECTED) {
  delay(500);
}
```

If, when building the test, the environment variables contained the login and password for the local access point, then they will be compiled into the test firmware and used before executing all tests.

The final step will be to disable this test by default. I don't expect anyone who wants to build a project will test FOTA, and I don't really want to run a test every time I build. For this purpose, PlatformIO has support for disabling tests!

```
test_ignore = fota, testfirmware
```

```testfirmware``` - this is another test that is not really a test, but the same program that does nothing and is used to test FOTA.

This all sounds very complicated, but the component itself is quite complex and does a lot of things that I would like to check automatically. I found so many bugs when I was writing these tests! But now the update works perfectly.

{{< youtube _DowEhVwboI >}}
