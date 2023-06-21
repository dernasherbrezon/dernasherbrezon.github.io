---
title: "Тестирование дисков для Raspberrypi - Часть 2"
date: 2023-06-20T22:01:18+01:00
draft: false
chartjs: true
tags:
  - raspberrypi
  - тестирование
  - администрирование
---

В [первой части]({{< ref "/test-disks-raspberrypi" >}}) я так и не понял какой диск мне ставить в Raspberrypi. С одной стороны обычные флэшки очень энергоэффективны, но медленные, а с другой, диски очень быстрые, но потребляют слишком много энергии. Во второй части (и, надеюсь, последней) я решил не выдумывать, а пошёл на [The PiHut](https://thepihut.com/products/wd-green-240gb-2-5-ssd) и купил WD Green SSD 240Gb.

![](/img/test-disks-raspberrypi2/1.jpg)

## Тестирование

Методология тестирования совсем не изменилась со времён первой части:

 * Подключал диск
 * Выполнял измерение ```fio --name=write --ioengine=posixaio --rw=write --bs=4k --size=1g --numjobs=1 --runtime=30 --time_based --status-interval=1 --output-format=terse --output=file.csv```
 * Копировал файл ```file.csv``` в надёжное место
 * Отключал диск

Если сравнивать со скоростями дисков из предыдущего поста, то получается следующая картина:

{{< chartjs url="/static/img/test-disks-raspberrypi/bw-iops.json" id="bs_vs_iops" title="Последовательная запись" datasource="storejet_iops" datasourceLabel="storejet" datasource2="apacer_iops" datasource2Label="apacer" datasource3="seagate_iops" datasource3Label="seagate" datasource4="wd_rpi3_iops" datasource4Label="WD Green" yAxisLabel="IOPS" yAxisUnit="" staticSrc="/img/test-disks-raspberrypi2/bs_vs_iops.png">}}

Ну такое. Скорость чуть выше, но не космическая. И совсем недотягивает до скоростей MacBook. Чтобы, хоть как-то разнообразить сравнение, я решил протестировать SSD на разных версиях Raspberrypi. И вот, что получилось:

{{< chartjs url="/static/img/test-disks-raspberrypi/bw-iops.json" id="bs_vs_iops2" title="Последовательная запись" datasource="wd_rpi1_iops" datasourceLabel="Raspberrypi 1b" datasource2="wd_rpi3_iops" datasource2Label="Raspberrypi 3b+" datasource3="wd_rpi4_iops" datasource3Label="Raspberrypi 4" yAxisLabel="IOPS" yAxisUnit="" staticSrc="/img/test-disks-raspberrypi2/bs_vs_iops2.png">}}

UAS творит чудеса. Скорость стабильная и высокая. [Согласно Википедии](https://ru.wikipedia.org/wiki/USB_Attached_SCSI), UAS добавляет поддержку каких-то потоков и очередей. Видимо это позволяет эффективнее буферизовать данные перед отправкой. А на принимающей стороне эффективно и параллельно их записывать.

```
usb 2-1: new SuperSpeed USB device number 2 using xhci_hcd
usb 2-1: New USB device found, idVendor=174c, idProduct=55aa, bcdDevice= 1.00
usb 2-1: New USB device strings: Mfr=2, Product=3, SerialNumber=1
usb 2-1: Product: USB 3.0 TOSATA
usb 2-1: Manufacturer: ASMT
usb 2-1: SerialNumber: 0000000000A3
scsi host0: uas
scsi 0:0:0:0: Direct-Access     ASMT     USB 3.0 TOSATA   0    PQ: 0 ANSI: 6
sd 0:0:0:0: [sda] 468862128 512-byte logical blocks: (240 GB/224 GiB)
sd 0:0:0:0: [sda] Write Protect is off
sd 0:0:0:0: [sda] Mode Sense: 43 00 00 00
sd 0:0:0:0: [sda] Write cache: enabled, read cache: enabled, doesn't support DPO or FUA
sd 0:0:0:0: [sda] Optimal transfer size 33553920 bytes
```

При подключении к Raspberrypi 3b+ в dmesg появляется сообщение:

```
usb 1-1.3: new high-speed USB device number 5 using dwc_otg
usb 1-1.3: New USB device found, idVendor=174c, idProduct=55aa, bcdDevice= 1.00
usb 1-1.3: New USB device strings: Mfr=2, Product=3, SerialNumber=1
usb 1-1.3: Product: USB 3.0 TOSATA
usb 1-1.3: Manufacturer: ASMT
usb 1-1.3: SerialNumber: 0000000000A3
usb 1-1.3: The driver for the USB controller dwc_otg_hcd does not support scatter-gather which is
usb 1-1.3: required by the UAS driver. Please try an other USB controller if you wish to use UAS.
usb-storage 1-1.3:1.0: USB Mass Storage device detected
usb-storage 1-1.3:1.0: Quirks match for vid 174c pid 55aa: 400000
scsi host0: usb-storage 1-1.3:1.0
scsi 0:0:0:0: Direct-Access     ASMT     USB 3.0 TOSATA   0    PQ: 0 ANSI: 6
```

USB2.0 действительно не поддерживает UAS.

Что интересно, в Raspberrypi 1B, скорость того же самого диска значительно меньше. Такое ощущение, что скорость записи упирается в частоту процессора.

## Потребление энергии

Во всех трёх Raspberrypi диск потреблял примерно одинаковое количество энергии. А вот, если сравнивать с другими дисками, то получается следующая картина:

{{< chartjs url="/static/img/test-disks-raspberrypi/current.json" id="current_test" title="IOPS на один миллиампер" datasource="storejet_rate" datasourceLabel="storejet" datasource2="apacer_rate" datasource2Label="apacer" datasource3="seagate_rate" datasource3Label="seagate" datasource4="sundisk_rate" datasource4Label="sundisk" datasource5="wd_rpi4_rate" datasource5Label="WD Green" yAxisLabel="IOPS/мА" yAxisUnit="" staticSrc="/img/test-disks-raspberrypi2/current_test.png">}}
 
За счёт того, что скорость записи в Raspberrypi 4 больше при том же потреблении энергии, WD Green выиграл в общем зачёте!

## Выводы

Буду использовать WD Green.