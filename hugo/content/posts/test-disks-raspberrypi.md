---
title: "Тестирование дисков для Raspberrypi"
date: 2023-06-14T21:19:18+01:00
draft: false
chartjs: true
tags:
  - raspberrypi
  - тестирование
  - администрирование
---

Порой сидишь себе программируешь никого не трогаешь, а потом внезапно хочется встать и громко возмутиться "Да сколько уже можно это терпеть!". Такое случилось и со мной, во время невероятно длинной распаковки ядра линукса в Raspberrypi. Всё началось с того, что мне нужно было померить производительность драйвера для airspy mini, который по-умолчанию устанавливается в Debian buster. Делается это двумя командами. Первая нужна, чтобы найти PID процесса для мониторинга:

```
ps aux|grep sdr_server
```

Вторая нужна, чтобы записать статистику вызовов функций в файл для анализа:

```
perf record -F 99 -p 31786  -g -- sleep 10
```

Однако, в этот раз всё пошло не так:

```
/usr/bin/perf: line 13: exec: perf_5.15: not found
E: linux-perf-5.15 is not installed.
```

Эта ошибка случается, когда установленная команда ```perf``` несовместима с текущим ядром линукса. Такое бывает, когда приезжает новое ядро, оно автоматически устанавливается, а пакет ```perf``` не обновляется. К сожалению, в debian не появляется новая версия пакета для новой версии ядра, поэтому приходится собирать его самому. В этом нет ничего сложно, кроме злосчастной распаковки исходников ядра линукса. Она занимает вечность, так как в Raspberrypi по-умолчанию система установлена на sdcard. Но после того, как произошла распаковка, сборка достаточно проста:

```
sudo apt install libunwind-dev libbfd-dev libdw-dev libbz2-dev libdwarf-dev
make -C linux-5.15.32/tools/perf/
```

Итак, пока шли эти нескончаемые ~40 секунд, я успел проверить почту, посмотреть новости и придумать план: подключить жёсткий диск к Raspberrypi на постоянной основе и вести там свои дела. Но как выбрать правильный? Я решил собрать все диски, которые завалялись у меня дома, и протестировать!

## Диски

Диск номер один, тот, который лежал ближе всего - [Transcend 320GB StoreJet 25M](https://www.bhphotovideo.com/c/product/657297-REG/Transcend_TS320GSJ25M_320GB_StoreJet_25M_Portable.html). Ничего особенного. По заверениям производителя поддерживает USB 2.0. Да, это очень старый диск. Почему-то определяется как JMicron JM20329 SATA Bridge. Ну и ладно.

```
Bus 001 Device 015: ID 152d:2329 JMicron Technology Corp. / JMicron USA Technology Corp. JM20329 SATA Bridge
```

Диск номер два, Apple Flash SSD из MacBook Air вставленный в [noname enclosure](https://www.aliexpress.com/item/1005004402300323.html?spm=a2g0o.order_detail.order_detail_item.3.18387d56MWOtf4). Позволяет подключаться по USB-C как обычный жёсткий диск.

Флэшка от Apacer Technology. Невероятно древняя. Позволяет записывать целый гигабайт данных!

```
Bus 001 Device 004: ID 1005:b113 Apacer Technology, Inc. Handy Steno/AH123 / Handy Steno 2.0/HT203
```

Флэшка от Super Top microSD card reader. Почему-то не смогла определится. Пусть полежит, возможно, её время ещё не пришло.

Внешний жёсткий диск [Seagate 1teap6-500](https://www.amazon.co.uk/Seagate-Expansion-Portable-PlayStation-STEA2000400/dp/B00TKFEE5S). Где-то написано 5400 RPM и USB 1.1, а где-то 5400 RPM и USB 3.0. Не беда, я же собираюсь протестировать фактическую скорость, зачем мне спецификации?

```
Bus 001 Device 009: ID 0bc2:2322 Seagate RSS LLC SRD0NF1 Expansion Portable (STEA)
```

SD карта [SanDisk Ultra 32 GB microSDHC Class 10, U1](https://www.amazon.co.uk/SanDisk-microSDHC-Memory-Adapter-Performance/dp/B073JWXGNT). Какое сложное название товара и много параметров, наверное, круто.

## Тестирование

Для тестирования я выбрал утилиту [fio](https://fio.readthedocs.io/en/latest/). Она поддерживает миллион параметров, которые мне совершенно не нужны - то, что нужно. Устанавливается как обычно:

```
sudo apt install fio
```

Далее для каждого диска я делал следующее:

 * Подключал диск
 * Выполнял измерение ```fio --name=write --ioengine=posixaio --rw=write --bs=4k --size=1g --numjobs=1 --runtime=30 --time_based --status-interval=1 --output-format=terse --output=file.csv```
 * Копировал файл ```file.csv``` в надёжное место
 * Отключал диск
 
Как видно из команды запуска ```fio```, я тестировал простую последовательную запись. Ничего выдающегося.

В результате у меня получилось следующее:

{{< chartjs url="/static/img/test-disks-raspberrypi/bw-iops.json" id="bs_vs_iops" title="Последовательная запись" datasource="storejet_iops" datasourceLabel="storejet" datasource2="apacer_iops" datasource2Label="apacer" datasource3="seagate_iops" datasource3Label="seagate" datasource4="sundisk_iops" datasource4Label="sundisk" yAxisLabel="IOPS" yAxisUnit="" staticSrc="/img/test-disks-raspberrypi/bs_vs_iops.png">}}

Как говорится "Начали за здравие, кончили за упокой". Видимо сначала шла запись в какой-то внутренний буфер, поэтому быстро. А как только он закончился, то сразу стало медленно.

Как и ожидалось, лучшие результаты показали внешние диски, которые разрабатывались быть внешними дисками.

Кстати на графике нет Apple Flash SSD, так как у меня не получилось завести его под Raspberrypi. Чего я только не перепробовал: и подключение через хаб с активным питанием, и разные опции ядра вроде ```usb-storage.quirks=152d:a586:u``` - ничего не помогло. Этот накопитель потребляет очень много электричества и Raspberrypi просто не может выдать столько через USB порты:

```
[643278.399078] usb 1-1.2: USB disconnect, device number 14
[643390.016152] usb 1-1-port2: over-current change #1
[643392.321150] usb 1-1-port2: over-current change #2
[643393.415433] hwmon hwmon1: Undervoltage detected!
[643399.655459] hwmon hwmon1: Voltage normalised
[643403.330147] usb 1-1-port2: over-current change #3
[643422.019032] usb 1-1-port2: over-current change #4
```

Но если его подключить к Macbook AIR, то наблюдается странное:

{{< chartjs url="/static/img/test-disks-raspberrypi/jmicron.json" id="jmicron" title="Apple Flash SSD из MacBook Air" datasource="jmicron_no_power_iops" datasourceLabel="No power" datasource2="jmicron_power_iops" datasource2Label="Powered" yAxisLabel="IOPS" yAxisUnit="" staticSrc="/img/test-disks-raspberrypi/jmicron.png">}}

Оказывается скорость записи на диск зависит от того, подключен ли ноутбук в сеть или нет! Удивительно.

А что, если добавить внутренний SSD моего Apple MacBook Air M1? Никто ведь не утверждал, что сравнение будет честным.

{{< chartjs url="/static/img/test-disks-raspberrypi/bw-iops.json" id="bs_vs_iops_2" title="Последовательная запись" datasource="storejet_iops" datasourceLabel="storejet" datasource2="apacer_iops" datasource2Label="apacer" datasource3="seagate_iops" datasource3Label="seagate" datasource4="jmicron_power_iops" datasource4Label="External MacBook SSD"  datasource5="macbook_iops" datasource5Label="Macbook Air" yAxisLabel="IOPS" yAxisUnit="" staticSrc="/img/test-disks-raspberrypi/bs_vs_iops_2.png">}}

Скорость нового SSD в среднем в 3 раза больше, чем старые внешние HDD и в 2 раза больше, чем старый SSD от Apple. Не то, чтобы мне нужна была такая мощь в Raspberrypi, но хочется.

К слову о мощности, а что, если померить количество IOPS на один миллиампер потребляемого тока? Raspberrypi - это же про низкое потребление в компактном форм-факторе. Легко! Для этого я взял свой [USB тестер A3-B]({{< ref "/smart-usb-meter-a3-b" >}}) и померил некоторые диски:

{{< chartjs url="/static/img/test-disks-raspberrypi/current.json" id="current_test" title="Потребление тока в режиме последовательной записи" datasource="storejet_current" datasourceLabel="storejet" datasource2="apacer_current" datasource2Label="apacer" datasource3="seagate_current" datasource3Label="seagate" datasource4="sundisk_current" datasource4Label="sundisk" yAxisLabel="Ток" yAxisUnit="мА" staticSrc="/img/test-disks-raspberrypi/current_test.png">}}

Самый энергоэффективной оказалась обычная флэшка. Она потребляет ~90мА. Внешние диски ожидаемо более прожорливые. 

Кстати, seagate при той же скорости записи, что и storejet, тратит гораздо меньше энергии в режиме простоя. Хозяюшке на заметку.

А если поделить количество IOPS на мА*1000, то получится следующий график:

{{< chartjs url="/static/img/test-disks-raspberrypi/current.json" id="current_test2" title="IOPS на один миллиампер" datasource="storejet_rate" datasourceLabel="storejet" datasource2="apacer_rate" datasource2Label="apacer" datasource3="seagate_rate" datasource3Label="seagate" datasource4="sundisk_rate" datasource4Label="sundisk" yAxisLabel="IOPS/мА" yAxisUnit="" staticSrc="/img/test-disks-raspberrypi/current_test2.png">}}

И опять победила обычная флэшка. 

Тут правда есть один нюанс: когда тест заканчивается, данные продолжают писаться. А значит тратится энергия. Поэтому по-хорошему нужно было бы померить потребление энергии в режиме ```direct=true``` при записи файла фиксированного размера. Не очень понятно, будет ли скорость с большим потреблением энергии эффективнее долгой записи, но с малым потреблением энергии. Возможно, это исследование для отдельной статьи.

## Выводы

Всё равно непонятно какой диск подключать. Флэшка выглядит заманчиво, но что, если есть специальные внешние диски рассчитанные на низкое энергопотребление? Возможно, [WD purple](https://www.amazon.co.uk/WD-Purple-3-5-SATA-5400rpm/dp/B071KVB4F8?th=1)?

