---
title: "Отладка приложений в Debian"
date: 2022-07-01T22:19:18+01:00
draft: false
tags:
  - c
  - deb
  - администрирование
  - sdr-modem
---
Последние несколько месяцев я вожусь с [sdr-modem](https://github.com/dernasherbrezon/sdr-modem) и пытаюсь запустить его в связке с [r2cloud](https://github.com/dernasherbrezon/r2cloud). И вот, когда я уже думал, что все тесты прошли, билд на github actions собирается, оно падает с segmentation fault. Но я не стал падать духом и решил воспользоваться случаем, чтобы изучить отладку приложений в Debian.

## Основы

Итак, для того, чтобы отладка показала хоть что-то полезное, необходимо скомпилировать приложение с отладочной информацией. В противном случае будет что-то вроде этого:

```
Thread 1 (Thread 0x76f035a0 (LWP 3706)):
#0  0x76ddca3c in __GI___pthread_timedjoin_ex (threadid=1991734368, thread_return=0x0, abstime=<optimized out>, block=<optimized out>) at pthread_join_common.c:89
#1  0x00014958 in main ()
```

Для того чтобы добавить отладочную информацию, надо скомпилировать приложение с параметром "-g".

## Сборка .deb пакета

Но не всё так просто. Дело в том, что приложение с отладочной информацией может занимтаь почти в 6 раз больше места! Для примера я скомпилировал sdr-modem с отладочной информацией:

```
:~/git/sdr-modem $ ls -lh obj-arm-linux-gnueabihf/sdr_modem
-rwxr-xr-x 1 pi pi 591K Jun 29 16:23 obj-arm-linux-gnueabihf/sdr_modem
```

И без:

```
:~/git/sdr-modem $ ls -lh debian/sdr-modem/usr/bin/sdr_modem
-rwxr-xr-x 1 pi pi 103K Jun 29 16:24 debian/sdr-modem/usr/bin/sdr_modem
```

Распространять такие приложения достаточно накладно, поэтому в Debian решили выносить её в отдельный .deb пакет. При сборке debhelper определяет, что пакет собирается cmake, и запускает команду [strip](https://sourceware.org/binutils/docs/binutils/strip.html). Эта команда удаляет из всех запускаемых и библиотечных файлов отладочную информацию и помещает её в отдельные файлы. Эти файлы пакуются в отдельные .deb пакеты и могут устанавливаться отдельно. 

```
Get:1 http://r2cloud.s3.amazonaws.com buster/main armhf sdr-modem-dbgsym armhf 1.0.69-69~buster [195 kB]
Get:2 http://r2cloud.s3.amazonaws.com buster/main armhf sdr-modem armhf 1.0.69-69~buster [48.5 kB]
```

В сжатом виде бинарники занимают уже 48кбайт и 195кбайт. Так как отладочная информация нужна не всем и только в случае ошибок в программе, такой подход позволяет существенно сэкономить место на диске и ускорить установку.

В моём примере вся отладочная информация будет запакована в ```sdr-modem-dbgsym``` и будет находиться в папке:

```
/usr/lib/debug/.build-id/92/7243e5cc114d15d2eb698954100cae604baca8.debug
```

Это специальный путь, который понимает gdb. ```927243e5cc114d15d2eb698954100cae604baca8``` - это build-id - специальный уникальный идентификатор сборки. Он прописывается в бинарник, и по нему gdb будет искать отладочные файлы.

```
file /usr/bin/sdr_modem
/usr/bin/sdr_modem: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0, BuildID[sha1]=927243e5cc114d15d2eb698954100cae604baca8, stripped
```

## GDB

Если gdb не сможет распознать stacktrace ошибки, то достаточно установить дебаг-пакет и запустить ещё раз:

```
sudo apt install sdr-modem-dbgsym
gdb /usr/bin/sdr_modem sdrmodem.coredump
```

После этого debug информация будет подхвачена:

```
(gdb) thread apply all bt

Thread 1 (Thread 0x76fd05a0 (LWP 19529)):
#0  0x76ea9a3c in __GI___pthread_timedjoin_ex (threadid=1992574048, thread_return=thread_return@entry=0x0, abstime=abstime@entry=0x0, block=block@entry=true) at pthread_join_common.c:89
#1  0x76ea9884 in __pthread_join (threadid=<optimized out>, thread_return=thread_return@entry=0x0) at pthread_join.c:24
#2  0x00016ba8 in tcp_server_join_thread (server=<optimized out>) at /home/pi/actions-runner/_work/sdr-modem/sdr-modem/src/tcp_server.c:813
#3  0x00014990 in main (argc=<optimized out>, argv=<optimized out>) at /home/pi/actions-runner/_work/sdr-modem/sdr-modem/src/main.c:40
```

В данном примере видно, что поток ```Thread 1``` ожидает завершения другого в файле ```tcp_server.c``` и строке 813. Правда, отладочная информацию содержит полный путь до файла во время компиляции. Чтобы сделать аккуратно, можно добавить [debug-prefix-map](https://gcc.gnu.org/onlinedocs/gcc/Debugging-Options.html) опцию во флаги компиляции:

```
-fdebug-prefix-map=$(pwd)=.
```

Результат получится следующий:

```
Thread 1 (Thread 0x76fd05a0 (LWP 19529)):
#0  0x76ea9a3c in __GI___pthread_timedjoin_ex (threadid=1992574048, thread_return=thread_return@entry=0x0, abstime=abstime@entry=0x0, block=block@entry=true) at pthread_join_common.c:89
#1  0x76ea9884 in __pthread_join (threadid=<optimized out>, thread_return=thread_return@entry=0x0) at pthread_join.c:24
#2  0x00016ba8 in tcp_server_join_thread (server=<optimized out>) at ./src/tcp_server.c:813
#3  0x00014990 in main (argc=<optimized out>, argv=<optimized out>) at ./src/main.c:40
```

## Особенности

Если проект скомпилирован без отладочной информации, то debhelper всё равно создаст отдельный пакет! Он будет содержать всё те же файлы, но gdb не сможет загрузить отладочную информацию:

```
Reading symbols from /usr/lib/debug/.build-id/92/7243e5cc114d15d2eb698954100cae604baca8.debug...(no debugging symbols found)...done.
```