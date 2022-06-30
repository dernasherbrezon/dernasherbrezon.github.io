---
title: "Привязка systemd сервиса к устройству"
date: 2022-05-21T21:54:18+01:00
draft: false
tags:
  - поворотное устройство
  - raspberrypi
  - администрирование
---
В одном из [постов про поворотное устройство]({{< ref "/rotator-for-r2cloud" >}}) я вскользь упомянул настройку rotctrld. rotctrld - это небольшой демон, который открывает TCP порт и позволяет отправлять команды в tty-устройство. Я написал небольшой systemd конфиг, чтобы демон стартовал и рестартовал во время загрузки raspberrypi.

```
[Unit]
Description=rotctrld Service

[Service]
WorkingDirectory=/home/pi/r2cloud/
ExecStart=rotctld --model=1401 --port=4533 --listen-addr=127.0.0.1 --rot-file=/dev/ttyUSB0
Restart=always
User=pi
Group=pi

[Install]
WantedBy=multi-user.target
```

Однако, со временем стали всплывать достаточно неприятные моменты в обслуживании. Например, поворотное устройство иногда определялось как ```/dev/ttyUSB1```. Тогда приходилось либо перетыкать его в другой порт, либо логиниться на устройство, менять конфиг systemd и рестартовать. 

Или вот ещё один пример, при старте системы устройство не подключено. systemd пытается стартовать демон несколько раз и, несмотря на ```Restart=always```, отчаивается. Даже если я подключил устройство позднее, демон уже может не работать. Чтобы это решить, я сначала подключал устройство, а затем стартовал raspberrypi.

Это всё крайне неудобно, поэтому я решил разобраться с этим.

## UDEV

Для того чтобы устройство определялось под одним и тем же именем, нужно привязать идентификатор USB устройства к названию девайса. 

Идентификатор USB устройства можно получить с помощью команды ```lsusb```:

```
pi@rasp-bullseye:~ $ lsusb
Bus 001 Device 004: ID 067b:2303 Prolific Technology, Inc. PL2303 Serial Port / Mobile Action MA-8910P
Bus 001 Device 003: ID 0424:ec00 Microchip Technology, Inc. (formerly SMSC) SMSC9512/9514 Fast Ethernet Adapter
Bus 001 Device 002: ID 0424:9514 Microchip Technology, Inc. (formerly SMSC) SMC9514 Hub
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
```

Поворотное устройство определяется как ```Prolific Technology, Inc. PL2303 Serial Port``` с идентификатором  ```067b:2303```.

Далее необходимо создать конфиг udev ```/etc/udev/rules.d/99-usb-rotator.rules```, который содержит следующее:

```
SUBSYSTEM=="tty", ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", SYMLINK+="ttyRotator", TAG+="systemd", ENV{SYSTEMD_WANTS}="rotctrld.service"
```

В нём написано, что нужно создать symlink ```/dev/ttyRotator``` для устройства ```067b:2303```. Ещё в этом правиле написано стартовать ```rotctrld.service```, при появлении устройства. Крайне полезная вещь!

## systemd

Последним штрихом будет остановка сервиса, если устройство отключено. Для этого необходимо добавить следующую строчку в rotctrld сервис:

```
[unit]
...
StopWhenUnneeded=true
```

А ещё необходимо переключить сервис на использование симлинка:

```
ExecStart=rotctld --model=1401 --port=4533 --listen-addr=127.0.0.1 --rot-file=/dev/ttyRotator
```

## Результаты

В результате при подключении поворотного устройства в логах будет следующее:

```
May 21 21:36:29 rasp-bullseye kernel: pl2303 1-1.2:1.0: pl2303 converter detected
May 21 21:36:29 rasp-bullseye kernel: usb 1-1.2: pl2303 converter now attached to ttyUSB0
May 21 21:36:29 rasp-bullseye mtp-probe[849]: checking bus 1, device 6: "/sys/devices/platform/soc/3f980000.usb/usb1/1-1/1-1.2"
May 21 21:36:29 rasp-bullseye mtp-probe[849]: bus: 1, device: 6 was not an MTP device
May 21 21:36:29 rasp-bullseye systemd[1]: Started rotctrld Service.
```

А при отключении:

```
May 21 21:36:04 rasp-bullseye kernel: usb 1-1.2: USB disconnect, device number 5
May 21 21:36:04 rasp-bullseye kernel: pl2303 ttyUSB1: pl2303 converter now disconnected from ttyUSB1
May 21 21:36:04 rasp-bullseye kernel: pl2303 1-1.2:1.0: device disconnected
May 21 21:36:04 rasp-bullseye systemd[1]: Stopping rotctrld Service...
May 21 21:36:04 rasp-bullseye systemd[1]: rotctrld.service: Succeeded.
May 21 21:36:04 rasp-bullseye systemd[1]: Stopped rotctrld Service.
```

Казалось бы, небольшие изменения в конфигурации, но насколько они делают жизнь проще! А ещё я крайне удивлён мощью systemd. Несмотря на всю критику, он позволяет сделать подобную функциональность всего с помощью пары строчек в конфигурации.